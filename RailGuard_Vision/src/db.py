"""SQLite persistence layer and review management for RailGuard Vision alerts."""

from __future__ import annotations

import contextlib
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional, Tuple


@dataclass
class AlertRecord:
    """Represents a persisted alert record in SQLite."""

    id: int
    timestamp: str
    camera_id: str
    track_id: int
    object_class: str
    event_duration: float
    reason: str
    snapshot_path: str
    clip_path: Optional[str]
    review_status: str  # 'unreviewed', 'verified', 'false_alarm'
    cleared_timestamp: Optional[str] = None
    created_at: Optional[str] = None


class AlertDatabaseManager:
    """Thread-safe SQLite database manager for security alerts."""

    def __init__(self, db_path: str = "data/security_alerts.db") -> None:
        self.db_path = Path(db_path).resolve()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.init_db()

    @contextlib.contextmanager
    def _get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        conn = sqlite3.connect(str(self.db_path), timeout=10.0)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def init_db(self) -> None:
        """Create database schema if not present."""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS alerts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    camera_id TEXT NOT NULL,
                    track_id INTEGER NOT NULL,
                    object_class TEXT NOT NULL,
                    event_duration REAL NOT NULL,
                    reason TEXT NOT NULL,
                    snapshot_path TEXT NOT NULL,
                    clip_path TEXT,
                    review_status TEXT NOT NULL DEFAULT 'unreviewed',
                    cleared_timestamp TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """
            )
            cursor.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_alerts_camera_track
                ON alerts(camera_id, track_id);
                """
            )
            cursor.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_alerts_review_status
                ON alerts(review_status);
                """
            )
            conn.commit()

    def insert_alert(
        self,
        timestamp: str,
        camera_id: str,
        track_id: int,
        object_class: str,
        event_duration: float,
        reason: str,
        snapshot_path: str,
        clip_path: Optional[str] = None,
        review_status: str = "unreviewed",
        cleared_timestamp: Optional[str] = None,
    ) -> int:
        """Insert a newly raised alert into SQLite using parameterized query."""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                INSERT INTO alerts (
                    timestamp, camera_id, track_id, object_class,
                    event_duration, reason, snapshot_path, clip_path,
                    review_status, cleared_timestamp
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                (
                    timestamp,
                    camera_id,
                    track_id,
                    object_class,
                    event_duration,
                    reason,
                    snapshot_path,
                    clip_path,
                    review_status,
                    cleared_timestamp,
                ),
            )
            conn.commit()
            return int(cursor.lastrowid)

    def update_cleared_timestamp(
        self, track_id: int, camera_id: str, cleared_timestamp: str
    ) -> int:
        """Mark when an active alert for a track ID cleared."""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                UPDATE alerts
                SET cleared_timestamp = ?
                WHERE track_id = ? AND camera_id = ? AND cleared_timestamp IS NULL;
                """,
                (cleared_timestamp, track_id, camera_id),
            )
            conn.commit()
            return cursor.rowcount

    def update_review_status(self, alert_id: int, review_status: str) -> bool:
        """Update operator review decision ('verified' or 'false_alarm')."""
        if review_status not in ("verified", "false_alarm", "unreviewed"):
            raise ValueError(f"Invalid review_status: {review_status}")

        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                UPDATE alerts
                SET review_status = ?
                WHERE id = ?;
                """,
                (review_status, alert_id),
            )
            conn.commit()
            return cursor.rowcount > 0

    def get_alerts(
        self, limit: int = 100, unreviewed_only: bool = False
    ) -> List[AlertRecord]:
        """Fetch alert history ordered from newest to oldest."""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            if unreviewed_only:
                cursor.execute(
                    """
                    SELECT * FROM alerts
                    WHERE review_status = 'unreviewed'
                    ORDER BY id DESC LIMIT ?;
                    """,
                    (limit,),
                )
            else:
                cursor.execute(
                    """
                    SELECT * FROM alerts
                    ORDER BY id DESC LIMIT ?;
                    """,
                    (limit,),
                )
            rows = cursor.fetchall()

        records: List[AlertRecord] = []
        for r in rows:
            records.append(
                AlertRecord(
                    id=r["id"],
                    timestamp=r["timestamp"],
                    camera_id=r["camera_id"],
                    track_id=r["track_id"],
                    object_class=r["object_class"],
                    event_duration=r["event_duration"],
                    reason=r["reason"],
                    snapshot_path=r["snapshot_path"],
                    clip_path=r["clip_path"],
                    review_status=r["review_status"],
                    cleared_timestamp=r["cleared_timestamp"],
                    created_at=r["created_at"],
                )
            )
        return records

    def get_alert_by_id(self, alert_id: int) -> Optional[AlertRecord]:
        """Retrieve single alert by ID."""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM alerts WHERE id = ?;", (alert_id,))
            row = cursor.fetchone()
            if not row:
                return None
            return AlertRecord(
                id=row["id"],
                timestamp=row["timestamp"],
                camera_id=row["camera_id"],
                track_id=row["track_id"],
                object_class=row["object_class"],
                event_duration=row["event_duration"],
                reason=row["reason"],
                snapshot_path=row["snapshot_path"],
                clip_path=row["clip_path"],
                review_status=row["review_status"],
                cleared_timestamp=row["cleared_timestamp"],
                created_at=row["created_at"],
            )

    def get_false_alarm_rate(self) -> Tuple[Optional[float], int, int]:
        """Calculate false alarm rate from operator reviews.
        
        Returns:
            (false_alarm_rate [0.0 - 1.0], total_reviewed_count, false_alarm_count)
            Returns (None, 0, 0) if no alerts have been reviewed yet.
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT
                    COUNT(CASE WHEN review_status IN ('verified', 'false_alarm') THEN 1 END) AS total_reviewed,
                    COUNT(CASE WHEN review_status = 'false_alarm' THEN 1 END) AS false_alarms
                FROM alerts;
                """
            )
            row = cursor.fetchone()
            total_reviewed = int(row["total_reviewed"] or 0)
            false_alarms = int(row["false_alarms"] or 0)

        if total_reviewed == 0:
            return None, 0, 0

        rate = false_alarms / total_reviewed
        return rate, total_reviewed, false_alarms
