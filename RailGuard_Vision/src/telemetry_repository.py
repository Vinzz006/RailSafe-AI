"""Firebase Realtime Database Repository for physical sensor telemetry (ESP32 MQ sensors)."""

from __future__ import annotations

import datetime
import logging
import math
import re
from typing import Any, Dict, List, Optional, Tuple, Union

from src.firebase_service import get_realtime_db
from src.realtime_database_repository import sanitize_rtdb_key

logger = logging.getLogger("railguard_telemetry")


def validate_finite_number(val: Any, field_name: str) -> float:
    """Validate that val is a finite number (not NaN, Infinity, None, or string non-numeric)."""
    if val is None:
        raise ValueError(f"Value for '{field_name}' cannot be None.")
    try:
        f = float(val)
    except (TypeError, ValueError) as err:
        raise ValueError(f"Field '{field_name}' must be a valid number, got {val!r}") from err

    if math.isnan(f) or math.isinf(f):
        raise ValueError(f"Field '{field_name}' must be finite (cannot be NaN or Infinity).")
    return f


def normalize_sensor_channels(sensors_raw: Any) -> Dict[str, Dict[str, Any]]:
    """Normalize sensor channel dictionaries, supporting both firmware MQ names and legacy aliases.
    
    Firmware channels:
      - mq2_raw (Combustible gas / smoke)
      - mq4_raw (Natural gas / methane)
      - mq7_raw (Carbon monoxide)
    Legacy aliases:
      - sensor_1, sensor_2, sensor_3
      
    Returns a standardized dictionary mapping channel_key -> {"value": float, "unit": str, "label": str}
    """
    if not isinstance(sensors_raw, dict):
        raise ValueError("'sensors' payload must be a JSON object mapping channel names to values.")

    normalized: Dict[str, Dict[str, Any]] = {}

    for key, val in sensors_raw.items():
        if not key or not isinstance(key, str):
            continue
        clean_key = key.strip()

        if isinstance(val, (int, float)):
            f_val = validate_finite_number(val, clean_key)
            unit = "ADC count" if "raw" in clean_key else "raw"
            label = _get_default_label(clean_key)
            normalized[clean_key] = {"value": f_val, "unit": unit, "label": label}
        elif isinstance(val, dict):
            raw_num = val.get("value")
            if raw_num is not None:
                f_val = validate_finite_number(raw_num, clean_key)
                unit = str(val.get("unit") or ("ADC count" if "raw" in clean_key else "raw"))
                label = str(val.get("label") or _get_default_label(clean_key))
                normalized[clean_key] = {"value": f_val, "unit": unit, "label": label}
        elif isinstance(val, str):
            # Check if parseable number
            try:
                f_val = validate_finite_number(float(val), clean_key)
                unit = "ADC count" if "raw" in clean_key else "raw"
                label = _get_default_label(clean_key)
                normalized[clean_key] = {"value": f_val, "unit": unit, "label": label}
            except ValueError:
                pass

    return normalized


def _get_default_label(channel_key: str) -> str:
    labels = {
        "mq2_raw": "MQ-2 Combustible Gas/Smoke",
        "mq2": "MQ-2 Combustible Gas/Smoke",
        "mq4_raw": "MQ-4 Natural Gas/Methane",
        "mq4": "MQ-4 Natural Gas/Methane",
        "mq7_raw": "MQ-7 Carbon Monoxide",
        "mq7": "MQ-7 Carbon Monoxide",
        "sensor_1": "Sensor 1 (Aerosol/VOC)",
        "sensor_2": "Sensor 2 (Differential)",
        "sensor_3": "Sensor 3 (CO Reference)",
    }
    return labels.get(channel_key, channel_key.upper())


class RealtimeDatabaseTelemetryRepository:
    """Manages persistence and retrieval of physical sensor telemetry in Firebase Realtime Database."""

    def __init__(
        self,
        base_path: str = "railguard",
        db_root: Optional[Any] = None,
    ) -> None:
        clean = base_path.strip("/")
        self.base_path = clean or "railguard"
        self._root = db_root

    @property
    def root(self) -> Any:
        if self._root is None:
            self._root = get_realtime_db()
        return self._root

    @property
    def telemetry_history_ref(self) -> Any:
        """Reference to railguard/telemetry node."""
        return self.root.child(f"{self.base_path}/telemetry")

    @property
    def telemetry_latest_ref(self) -> Any:
        """Reference to railguard/telemetry_latest node."""
        return self.root.child(f"{self.base_path}/telemetry_latest")

    def check_readiness(self) -> bool:
        """Verifies access to Firebase Realtime Database telemetry paths."""
        try:
            _ = self.telemetry_latest_ref.order_by_key().limit_to_first(1).get()
            return True
        except Exception as e:
            logger.warning("Telemetry repository readiness check failed: %s", e)
            return False

    def ingest_reading(self, raw_data: Dict[str, Any]) -> Dict[str, Any]:
        """Ingests a single physical sensor telemetry frame into Realtime Database.
        
        Writes to:
          - railguard/telemetry/{device_id}/{reading_id} (History record)
          - railguard/telemetry_latest/{device_id} (Latest state, with out-of-order protection)
        """
        # Resolve device ID (accepting deviceId or device_id)
        raw_device_id = raw_data.get("deviceId") or raw_data.get("device_id")
        if not raw_device_id:
            raise ValueError("device_id or deviceId is required.")
        device_id = sanitize_rtdb_key(str(raw_device_id).strip())

        # Sequence validation
        seq_raw = raw_data.get("sequence")
        sequence = 0
        if seq_raw is not None:
            try:
                sequence = int(seq_raw)
                if sequence < 0:
                    raise ValueError("Sequence cannot be negative.")
            except (ValueError, TypeError) as err:
                raise ValueError(f"Invalid sequence: {seq_raw}") from err

        mode = str(raw_data.get("mode") or "hardware").lower()
        if mode not in ("hardware", "demo"):
            mode = "hardware"

        # Channels validation
        sensors_dict = normalize_sensor_channels(raw_data.get("sensors") or {})

        # Distinguish missing physical channels
        missing_channels: List[str] = []
        if isinstance(raw_data.get("missing_channels"), list):
            missing_channels = [str(c) for c in raw_data["missing_channels"] if c]
        elif mode == "hardware":
            for req in ("mq2_raw", "mq4_raw", "mq7_raw"):
                if req not in sensors_dict and req.replace("_raw", "") not in sensors_dict:
                    missing_channels.append(req)

        status_str = str(raw_data.get("status") or ("missing_telemetry" if missing_channels else "ok"))

        now_utc = datetime.datetime.now(datetime.timezone.utc)
        server_received_at = now_utc.isoformat()
        server_received_at_ms = int(now_utc.timestamp() * 1000)

        device_timestamp = raw_data.get("timestamp") or raw_data.get("device_timestamp")

        # Stable reading ID preventing duplicate insertion on client retry
        reading_id = f"seq_{sequence:08d}_{server_received_at_ms}"

        payload: Dict[str, Any] = {
            "id": reading_id,
            "device_id": device_id,
            "sequence": sequence,
            "mode": mode,
            "sensors": sensors_dict,
            "status": status_str,
            "missing_channels": missing_channels,
            "device_timestamp": str(device_timestamp) if device_timestamp else None,
            "server_received_at": server_received_at,
            "server_received_at_ms": server_received_at_ms,
        }

        # 1. Write to history node: railguard/telemetry/{device_id}/{reading_id}
        self.telemetry_history_ref.child(device_id).child(reading_id).set(payload)

        # 2. Update latest state safely with out-of-order check
        latest_ref = self.telemetry_latest_ref.child(device_id)

        def _update_latest_txn(current_val: Any) -> Any:
            if current_val is None:
                return payload
            if isinstance(current_val, dict):
                curr_seq = int(current_val.get("sequence", -1))
                curr_ts_ms = int(current_val.get("server_received_at_ms", -1))
                # If sequence numbers are provided (> 0), sequence is strictly authoritative
                if sequence > 0 and curr_seq > 0:
                    if sequence >= curr_seq:
                        return payload
                    return current_val
                # Otherwise fall back to server receipt timestamp
                if server_received_at_ms >= curr_ts_ms:
                    return payload
                return current_val
            return payload

        try:
            if hasattr(latest_ref, "transaction") and callable(getattr(latest_ref, "transaction")):
                latest_ref.transaction(_update_latest_txn)
            else:
                existing = latest_ref.get()
                new_val = _update_latest_txn(existing)
                latest_ref.set(new_val)
        except Exception as e:
            logger.warning("Error updating telemetry_latest for %s: %s; saving directly", device_id, e)
            latest_ref.set(payload)

        logger.debug("Ingested telemetry frame %s for device %s", reading_id, device_id)
        return payload

    def ingest_batch(self, readings_list: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Ingests a batch of telemetry frames, returning list of saved payloads."""
        if not readings_list or not isinstance(readings_list, list):
            raise ValueError("readings must be a non-empty list.")
        if len(readings_list) > 100:
            raise ValueError("Batch exceeds maximum size of 100 frames.")

        results: List[Dict[str, Any]] = []
        for item in readings_list:
            if isinstance(item, dict):
                saved = self.ingest_reading(item)
                results.append(saved)
        return results

    def get_latest_reading(self, device_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves the latest telemetry frame recorded for a device."""
        clean_id = sanitize_rtdb_key(device_id)
        data = self.telemetry_latest_ref.child(clean_id).get()
        if not data or not isinstance(data, dict):
            return None
        return data

    def get_history(self, device_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Retrieves bounded telemetry history for a device, sorted newest first."""
        clean_id = sanitize_rtdb_key(device_id)
        limit = max(1, min(limit, 500))

        raw_results: Dict[str, Any] = {}
        try:
            raw_results = (
                self.telemetry_history_ref.child(clean_id)
                .order_by_child("server_received_at_ms")
                .limit_to_last(limit)
                .get()
                or {}
            )
        except Exception as e:
            logger.warning("order_by_child query on telemetry failed: %s; falling back", e)
            raw_results = self.telemetry_history_ref.child(clean_id).get() or {}

        items: List[Dict[str, Any]] = []
        if isinstance(raw_results, dict):
            for k, val in raw_results.items():
                if isinstance(val, dict):
                    doc = dict(val)
                    doc["id"] = k
                    items.append(doc)
        elif isinstance(raw_results, list):
            for idx, val in enumerate(raw_results):
                if isinstance(val, dict):
                    doc = dict(val)
                    doc["id"] = doc.get("id") or str(idx)
                    items.append(doc)

        # Sort newest-first (descending by server_received_at_ms and sequence)
        items.sort(
            key=lambda x: (
                int(x.get("server_received_at_ms") or 0),
                int(x.get("sequence") or 0),
            ),
            reverse=True,
        )
        return items[:limit]
