"""
Alert Logging & Snapshot Storage Module.
Stores alert events in SQLite and CSV logs without transmitting data externally.
Saves cropped/annotated snapshots to disk when alerts are raised.
"""

import os
import csv
import sqlite3
import datetime
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import cv2
import numpy as np

from config import DB_PATH, CSV_LOG_PATH, SNAPSHOTS_DIR
from tracker import LuggageAlertEvent

logger = logging.getLogger("railway_luggage.alerts")


class AlertManager:
    def __init__(self, db_path: Path = DB_PATH, csv_path: Path = CSV_LOG_PATH):
        self.db_path = str(db_path)
        self.csv_path = str(csv_path)
        self._init_sqlite()
        self._init_csv()

    def _init_sqlite(self):
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    CREATE TABLE IF NOT EXISTS alerts (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp TEXT NOT NULL,
                        event_type TEXT NOT NULL,
                        track_id INTEGER NOT NULL,
                        object_class TEXT NOT NULL,
                        confidence REAL NOT NULL,
                        isolation_duration REAL NOT NULL,
                        distance_to_person REAL NOT NULL,
                        status TEXT NOT NULL,
                        snapshot_path TEXT,
                        acknowledged INTEGER DEFAULT 0
                    )
                    """
                )
                conn.commit()
        except Exception as e:
            logger.error(f"Failed to initialize SQLite alerts database: {e}")

    def _init_csv(self):
        if not os.path.exists(self.csv_path):
            try:
                with open(self.csv_path, mode="w", newline="", encoding="utf-8") as f:
                    writer = csv.writer(f)
                    writer.writerow([
                        "Timestamp",
                        "Event Type",
                        "Track ID",
                        "Object Class",
                        "Confidence",
                        "Isolation Duration (s)",
                        "Distance to Person (px)",
                        "Status",
                        "Snapshot Path",
                        "Acknowledged",
                    ])
            except Exception as e:
                logger.error(f"Failed to initialize CSV log: {e}")

    def log_alert(
        self,
        event: LuggageAlertEvent,
        frame: Optional[np.ndarray] = None,
    ) -> Dict:
        """
        Logs a new luggage alert, saves a snapshot if frame is provided, and updates storage.
        """
        now = datetime.datetime.now()
        iso_timestamp = now.isoformat(timespec="seconds")
        file_timestamp = now.strftime("%Y%m%d_%H%M%S")

        snapshot_path_str = ""
        if frame is not None:
            snapshot_filename = f"alert_bag_{event.track_id}_{file_timestamp}.jpg"
            full_snapshot_path = SNAPSHOTS_DIR / snapshot_filename
            try:
                # Annotate snapshot with bounding box & warning header
                annotated = frame.copy()
                x1, y1, x2, y2 = event.box
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 0, 255), 3)
                label = f"REVIEW ALERT: Track #{event.track_id} ({event.class_name})"
                cv2.putText(
                    annotated,
                    label,
                    (x1, max(y1 - 10, 20)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (0, 0, 255),
                    2,
                )
                cv2.imwrite(str(full_snapshot_path), annotated)
                snapshot_path_str = str(full_snapshot_path)
                logger.info(f"Saved alert snapshot to: {snapshot_path_str}")
            except Exception as e:
                logger.error(f"Failed to save snapshot: {e}")

        # Insert into SQLite
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    INSERT INTO alerts (
                        timestamp, event_type, track_id, object_class, confidence,
                        isolation_duration, distance_to_person, status, snapshot_path, acknowledged
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                    (
                        iso_timestamp,
                        "UNATTENDED_LUGGAGE",
                        event.track_id,
                        event.class_name,
                        event.confidence,
                        event.isolation_duration,
                        event.distance_to_person,
                        event.status,
                        snapshot_path_str,
                    ),
                )
                conn.commit()
                alert_id = cursor.lastrowid
        except Exception as e:
            logger.error(f"Error inserting alert into SQLite: {e}")
            alert_id = -1

        # Append to CSV
        try:
            with open(self.csv_path, mode="a", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow([
                    iso_timestamp,
                    "UNATTENDED_LUGGAGE",
                    event.track_id,
                    event.class_name,
                    event.confidence,
                    event.isolation_duration,
                    event.distance_to_person,
                    event.status,
                    snapshot_path_str,
                    0,
                ])
        except Exception as e:
            logger.error(f"Error appending alert to CSV: {e}")

        return {
            "id": alert_id,
            "timestamp": iso_timestamp,
            "track_id": event.track_id,
            "class_name": event.class_name,
            "duration": event.isolation_duration,
            "snapshot_path": snapshot_path_str,
            "status": event.status,
        }

    def get_recent_alerts(self, limit: int = 10) -> List[Dict]:
        """Fetches recent security alert records from SQLite."""
        alerts = []
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    SELECT id, timestamp, event_type, track_id, object_class,
                           confidence, isolation_duration, distance_to_person,
                           status, snapshot_path, acknowledged
                    FROM alerts
                    ORDER BY id DESC
                    LIMIT ?
                    """,
                    (limit,),
                )
                rows = cursor.fetchall()
                for r in rows:
                    alerts.append({
                        "id": r[0],
                        "timestamp": r[1],
                        "event_type": r[2],
                        "track_id": r[3],
                        "object_class": r[4],
                        "confidence": r[5],
                        "isolation_duration": r[6],
                        "distance_to_person": r[7],
                        "status": r[8],
                        "snapshot_path": r[9],
                        "acknowledged": bool(r[10]),
                    })
        except Exception as e:
            logger.error(f"Error reading alerts from SQLite: {e}")
        return alerts

    def acknowledge_alert(self, alert_id: int):
        """Marks alert as acknowledged in the database."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("UPDATE alerts SET acknowledged = 1 WHERE id = ?", (alert_id,))
                conn.commit()
        except Exception as e:
            logger.error(f"Error updating alert acknowledgment: {e}")

    def save_manual_snapshot(self, frame: np.ndarray, tag: str = "manual") -> str:
        """Saves a frame snapshot on manual user demand."""
        now = datetime.datetime.now()
        filename = f"{tag}_{now.strftime('%Y%m%d_%H%M%S')}.jpg"
        full_path = SNAPSHOTS_DIR / filename
        cv2.imwrite(str(full_path), frame)
        return str(full_path)
