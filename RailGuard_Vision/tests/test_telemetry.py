"""Unit tests for sensor telemetry normalization, repository logic, and validation."""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional
import pytest

from src.telemetry_repository import (
    RealtimeDatabaseTelemetryRepository,
    normalize_sensor_channels,
    validate_finite_number,
)


class MockRtdbChildRef:
    """Mock Realtime Database reference node for unit testing telemetry persistence."""

    def __init__(self, name: str, parent: Optional[MockRtdbChildRef] = None) -> None:
        self.name = name
        self.parent = parent
        self.children: Dict[str, MockRtdbChildRef] = {}
        self.data: Any = None
        self._order_by_child_field: Optional[str] = None
        self._limit_last: Optional[int] = None

    def child(self, path: str) -> MockRtdbChildRef:
        clean_path = path.strip("/")
        parts = clean_path.split("/")
        curr = self
        for p in parts:
            if p not in curr.children:
                curr.children[p] = MockRtdbChildRef(p, parent=curr)
            curr = curr.children[p]
        return curr

    def set(self, val: Any) -> None:
        self.data = val

    def get(self) -> Any:
        if self.data is not None:
            return self.data
        if self.children:
            out: Dict[str, Any] = {}
            for k, child in self.children.items():
                child_data = child.get()
                if child_data is not None:
                    out[k] = child_data
            return out if out else None
        return None

    def transaction(self, transform_fn: Any) -> Any:
        new_val = transform_fn(self.data)
        self.data = new_val
        return new_val

    def order_by_key(self) -> MockRtdbChildRef:
        return self

    def order_by_child(self, field: str) -> MockRtdbChildRef:
        ref = MockRtdbChildRef(self.name, self.parent)
        ref.children = self.children
        ref.data = self.data
        ref._order_by_child_field = field
        return ref

    def limit_to_first(self, n: int) -> MockRtdbChildRef:
        return self

    def limit_to_last(self, n: int) -> MockRtdbChildRef:
        ref = MockRtdbChildRef(self.name, self.parent)
        ref.children = self.children
        ref.data = self.data
        ref._order_by_child_field = self._order_by_child_field
        ref._limit_last = n
        return ref


class MockRtdbRoot:
    """Mock root for Realtime Database."""

    def __init__(self) -> None:
        self.root = MockRtdbChildRef("root")

    def child(self, path: str) -> MockRtdbChildRef:
        return self.root.child(path)


# ============================================================================
# Math & Finite Number Tests
# ============================================================================

def test_validate_finite_number_valid() -> None:
    assert validate_finite_number(0, "test") == 0.0
    assert validate_finite_number(4095, "test") == 4095.0
    assert validate_finite_number(12.34, "test") == 12.34
    assert validate_finite_number("123.45", "test") == 123.45


def test_validate_finite_number_rejections() -> None:
    with pytest.raises(ValueError, match="cannot be None"):
        validate_finite_number(None, "test")

    with pytest.raises(ValueError, match="cannot be NaN or Infinity"):
        validate_finite_number(float("nan"), "test")

    with pytest.raises(ValueError, match="cannot be NaN or Infinity"):
        validate_finite_number(float("inf"), "test")

    with pytest.raises(ValueError, match="cannot be NaN or Infinity"):
        validate_finite_number(float("-inf"), "test")

    with pytest.raises(ValueError, match="must be a valid number"):
        validate_finite_number("not_a_number", "test")


# ============================================================================
# Channel Normalization Tests
# ============================================================================

def test_normalize_firmware_channels() -> None:
    raw = {
        "mq2_raw": 1250,
        "mq4_raw": 840,
        "mq7_raw": 512,
    }
    normalized = normalize_sensor_channels(raw)
    assert len(normalized) == 3
    assert normalized["mq2_raw"]["value"] == 1250.0
    assert normalized["mq2_raw"]["unit"] == "ADC count"
    assert "Combustible" in normalized["mq2_raw"]["label"]

    assert normalized["mq4_raw"]["value"] == 840.0
    assert normalized["mq7_raw"]["value"] == 512.0


def test_normalize_actual_zero_preservation() -> None:
    raw = {
        "mq2_raw": 0,
        "mq4_raw": 0.0,
    }
    normalized = normalize_sensor_channels(raw)
    assert normalized["mq2_raw"]["value"] == 0.0
    assert normalized["mq4_raw"]["value"] == 0.0


def test_normalize_legacy_aliases() -> None:
    raw = {
        "sensor_1": 450,
        "sensor_2": 670,
        "sensor_3": 120,
    }
    normalized = normalize_sensor_channels(raw)
    assert "sensor_1" in normalized
    assert normalized["sensor_1"]["value"] == 450.0
    assert normalized["sensor_2"]["value"] == 670.0


def test_normalize_nested_dict_channels() -> None:
    raw = {
        "mq2_raw": {"value": 2048, "unit": "counts", "label": "Custom Label"},
    }
    normalized = normalize_sensor_channels(raw)
    assert normalized["mq2_raw"]["value"] == 2048.0
    assert normalized["mq2_raw"]["unit"] == "counts"
    assert normalized["mq2_raw"]["label"] == "Custom Label"


def test_normalize_invalid_type_raises() -> None:
    with pytest.raises(ValueError, match="must be a JSON object"):
        normalize_sensor_channels(["not", "a", "dict"])


# ============================================================================
# Telemetry Repository Logic Tests
# ============================================================================

def test_telemetry_repository_ingest_and_latest() -> None:
    mock_db = MockRtdbRoot()
    repo = RealtimeDatabaseTelemetryRepository(base_path="railguard", db_root=mock_db)

    reading = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
            "mq2_raw": 1200,
            "mq4_raw": 800,
            "mq7_raw": 450,
        },
    }

    saved = repo.ingest_reading(reading)
    assert saved["device_id"] == "RAILSAFE-ESP32-01"
    assert saved["sequence"] == 1
    assert saved["status"] == "ok"
    assert saved["missing_channels"] == []
    assert "server_received_at" in saved

    # Check latest retrieval
    latest = repo.get_latest_reading("RAILSAFE-ESP32-01")
    assert latest is not None
    assert latest["sequence"] == 1
    assert latest["sensors"]["mq2_raw"]["value"] == 1200.0


def test_telemetry_out_of_order_sequence_protection() -> None:
    mock_db = MockRtdbRoot()
    repo = RealtimeDatabaseTelemetryRepository(base_path="railguard", db_root=mock_db)

    # Ingest newer frame sequence 10
    repo.ingest_reading({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 10,
        "mode": "hardware",
        "sensors": {"mq2_raw": 2000, "mq4_raw": 1500, "mq7_raw": 900},
    })

    # Ingest delayed older frame sequence 5
    repo.ingest_reading({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 5,
        "mode": "hardware",
        "sensors": {"mq2_raw": 1000, "mq4_raw": 500, "mq7_raw": 300},
    })

    # Latest MUST retain sequence 10, not be downgraded to 5
    latest = repo.get_latest_reading("RAILSAFE-ESP32-01")
    assert latest is not None
    assert latest["sequence"] == 10
    assert latest["sensors"]["mq2_raw"]["value"] == 2000.0


def test_telemetry_missing_channels_detection_hardware_mode() -> None:
    mock_db = MockRtdbRoot()
    repo = RealtimeDatabaseTelemetryRepository(base_path="railguard", db_root=mock_db)

    # Ingest payload missing MQ-7
    saved = repo.ingest_reading({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
            "mq2_raw": 1500,
            "mq4_raw": 1200,
        },
    })
    assert saved["status"] == "missing_telemetry"
    assert "mq7_raw" in saved["missing_channels"]


def test_telemetry_batch_ingestion_and_limits() -> None:
    mock_db = MockRtdbRoot()
    repo = RealtimeDatabaseTelemetryRepository(base_path="railguard", db_root=mock_db)

    batch = [
        {
            "deviceId": "RAILSAFE-ESP32-01",
            "sequence": i,
            "mode": "hardware",
            "sensors": {"mq2_raw": 1000 + i, "mq4_raw": 500, "mq7_raw": 300},
        }
        for i in range(5)
    ]

    saved_batch = repo.ingest_batch(batch)
    assert len(saved_batch) == 5

    # Batch exceeding 100 frames must be rejected
    huge_batch = [{"deviceId": "DEV", "sequence": i, "sensors": {}} for i in range(101)]
    with pytest.raises(ValueError, match="exceeds maximum size"):
        repo.ingest_batch(huge_batch)

    with pytest.raises(ValueError, match="non-empty list"):
        repo.ingest_batch([])


def test_telemetry_history_retrieval() -> None:
    mock_db = MockRtdbRoot()
    repo = RealtimeDatabaseTelemetryRepository(base_path="railguard", db_root=mock_db)

    for i in range(1, 4):
        repo.ingest_reading({
            "deviceId": "RAILSAFE-ESP32-01",
            "sequence": i,
            "sensors": {"mq2_raw": 100 * i, "mq4_raw": 200, "mq7_raw": 300},
        })

    history = repo.get_history("RAILSAFE-ESP32-01", limit=2)
    assert len(history) == 2
    # Newest-first ordering
    assert history[0]["sequence"] >= history[1]["sequence"]


def test_telemetry_check_readiness() -> None:
    mock_db = MockRtdbRoot()
    repo = RealtimeDatabaseTelemetryRepository(base_path="railguard", db_root=mock_db)
    assert repo.check_readiness() is True
