"""Unit and integration tests for RailGuard Vision FastAPI Cloud Backend."""

from __future__ import annotations

import io
import os
import tempfile
from pathlib import Path
from typing import Generator

import pytest
from fastapi.testclient import TestClient

from app.api import app, config as api_config, db as api_db
from src.config import SecurityConfig, StorageConfig, SystemConfig
from src.db import AlertDatabaseManager


@pytest.fixture
def test_env() -> Generator[dict, None, None]:
    """Provide isolated temporary storage and database for API testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        db_file = tmp_path / "test_api_alerts.db"
        alerts_dir = tmp_path / "alerts"
        clips_dir = tmp_path / "clips"
        alerts_dir.mkdir(parents=True, exist_ok=True)
        clips_dir.mkdir(parents=True, exist_ok=True)

        # Configure test database
        test_db = AlertDatabaseManager(str(db_file))

        # Backup original globals
        orig_db = app.dependency_overrides.copy()
        orig_api_db = app.__dict__.get("db")
        
        # Override module globals for test
        import app.api as api_module
        prev_module_db = api_module.db
        prev_module_cfg = api_module.config

        api_module.db = test_db
        api_module.config.storage.db_path = str(db_file)
        api_module.config.storage.alerts_dir = str(alerts_dir)
        api_module.config.storage.clips_dir = str(clips_dir)
        api_module.config.security.api_token = "test-operator-token"
        api_module.config.security.agent_token = "test-agent-token"

        client = TestClient(app)

        yield {
            "client": client,
            "db": test_db,
            "tmp_path": tmp_path,
            "alerts_dir": alerts_dir,
            "clips_dir": clips_dir,
            "api_token": "test-operator-token",
            "agent_token": "test-agent-token",
        }

        # Restore module state
        api_module.db = prev_module_db
        api_module.config = prev_module_cfg


def test_health_check(test_env: dict) -> None:
    """Verify GET /health returns readiness without leaking secrets or paths."""
    client: TestClient = test_env["client"]
    res = client.get("/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "healthy"
    assert data["storage_ready"] is True
    assert "disclaimer" in data
    assert "FOR HUMAN REVIEW ONLY" in data["disclaimer"]
    # Ensure no internal paths or tokens are leaked
    body_str = res.text
    assert "test-operator-token" not in body_str
    assert "test-agent-token" not in body_str
    assert "test_api_alerts.db" not in body_str


def test_authentication_enforcement(test_env: dict) -> None:
    """Verify unauthenticated or invalid token requests are rejected with 401."""
    client: TestClient = test_env["client"]

    # 1. No token -> 401
    res = client.get("/api/alerts")
    assert res.status_code == 401
    assert "Unauthorized" in res.json()["detail"]

    # 2. Invalid token -> 401
    res_bad = client.get("/api/alerts", headers={"Authorization": "Bearer bad-token"})
    assert res_bad.status_code == 401

    # 3. Valid token -> 200
    res_ok = client.get(
        "/api/alerts",
        headers={"Authorization": f"Bearer {test_env['api_token']}"},
    )
    assert res_ok.status_code == 200
    assert isinstance(res_ok.json(), list)


def test_ingest_alert_valid_and_idempotent(test_env: dict) -> None:
    """Verify camera agent ingestion, evidence saving, and idempotency on event_uid."""
    client: TestClient = test_env["client"]
    agent_token = test_env["agent_token"]
    db: AlertDatabaseManager = test_env["db"]

    # Create dummy JPEG image
    fake_jpeg = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xff\xdb" + b"\x00" * 50

    form_data = {
        "event_uid": "EVT-CAM01-TRK42-20261011T010000Z",
        "timestamp": "2026-10-11T01:00:00Z",
        "camera_id": "CAM-PLATFORM-01",
        "track_id": "42",
        "object_class": "backpack",
        "event_duration": "18.5",
        "reason": "Stationary unattended luggage detected for > 15s",
    }
    files = {
        "snapshot": ("snap.jpg", io.BytesIO(fake_jpeg), "image/jpeg"),
    }
    headers = {"Authorization": f"Bearer {agent_token}"}

    # Step 1: Initial Ingest
    res = client.post("/api/ingest/alerts", data=form_data, files=files, headers=headers)
    assert res.status_code == 201
    data = res.json()
    assert data["status"] == "created"
    alert_id = data["alert_id"]
    assert alert_id > 0

    # Verify record in SQLite
    rec = db.get_alert_by_id(alert_id)
    assert rec is not None
    assert rec.track_id == 42
    assert rec.object_class == "backpack"
    assert rec.event_uid == "EVT-CAM01-TRK42-20261011T010000Z"
    assert Path(rec.snapshot_path).is_file()

    # Step 2: Idempotent Retry (Exact same event_uid re-transmitted)
    files2 = {"snapshot": ("snap.jpg", io.BytesIO(fake_jpeg), "image/jpeg")}
    res_retry = client.post("/api/ingest/alerts", data=form_data, files=files2, headers=headers)
    assert res_retry.status_code == 200
    retry_data = res_retry.json()
    assert retry_data["status"] == "already_exists"
    assert retry_data["alert_id"] == alert_id

    # Verify no duplicate rows were created in DB
    all_alerts = db.get_alerts()
    matching = [a for a in all_alerts if a.event_uid == "EVT-CAM01-TRK42-20261011T010000Z"]
    assert len(matching) == 1


def test_ingest_rejection_invalid_fields(test_env: dict) -> None:
    """Verify rejection of invalid fields or non-image snapshot."""
    client: TestClient = test_env["client"]
    agent_token = test_env["agent_token"]
    headers = {"Authorization": f"Bearer {agent_token}"}

    # Non-image file upload
    bad_files = {"snapshot": ("script.sh", io.BytesIO(b"echo hack"), "text/plain")}
    bad_data = {
        "event_uid": "EVT-BAD",
        "timestamp": "2026-10-11T01:00:00Z",
        "camera_id": "CAM-01",
        "track_id": "1",
        "object_class": "backpack",
        "event_duration": "5.0",
        "reason": "Test",
    }
    res = client.post("/api/ingest/alerts", data=bad_data, files=bad_files, headers=headers)
    assert res.status_code == 400
    assert "must be a valid image" in res.json()["detail"]


def test_ingest_clear_event(test_env: dict) -> None:
    """Verify POST /api/ingest/alerts/clear marks active alerts cleared."""
    client: TestClient = test_env["client"]
    agent_token = test_env["agent_token"]
    db: AlertDatabaseManager = test_env["db"]

    # Insert an active alert in SQLite
    aid = db.insert_alert(
        timestamp="2026-10-11T01:00:00Z",
        camera_id="CAM-CLR-01",
        track_id=105,
        object_class="suitcase",
        event_duration=20.0,
        reason="Test active alert",
        snapshot_path="dummy.jpg",
    )

    # Post clear notification
    clear_payload = {
        "camera_id": "CAM-CLR-01",
        "track_id": 105,
        "cleared_timestamp": "2026-10-11T01:05:00Z",
    }
    res = client.post(
        "/api/ingest/alerts/clear",
        json=clear_payload,
        headers={"Authorization": f"Bearer {agent_token}"},
    )
    assert res.status_code == 200
    assert res.json()["rows_updated"] >= 1

    updated = db.get_alert_by_id(aid)
    assert updated is not None
    assert updated.cleared_timestamp == "2026-10-11T01:05:00Z"


def test_operator_review_and_stats(test_env: dict) -> None:
    """Verify operator review updates ('verified', 'false_alarm') and running false alarm rate."""
    client: TestClient = test_env["client"]
    api_token = test_env["api_token"]
    db: AlertDatabaseManager = test_env["db"]
    headers = {"Authorization": f"Bearer {api_token}"}

    # Insert two test alerts
    a1 = db.insert_alert(
        timestamp="2026-10-11T01:00:00Z",
        camera_id="CAM-REV",
        track_id=1,
        object_class="backpack",
        event_duration=16.0,
        reason="Test 1",
        snapshot_path="snap1.jpg",
    )
    a2 = db.insert_alert(
        timestamp="2026-10-11T01:01:00Z",
        camera_id="CAM-REV",
        track_id=2,
        object_class="handbag",
        event_duration=17.0,
        reason="Test 2",
        snapshot_path="snap2.jpg",
    )

    # Review a1 as verified
    res1 = client.patch(
        f"/api/alerts/{a1}/review",
        json={"review_status": "verified"},
        headers=headers,
    )
    assert res1.status_code == 200
    assert res1.json()["review_status"] == "verified"

    # Review a2 as false_alarm
    res2 = client.patch(
        f"/api/alerts/{a2}/review",
        json={"review_status": "false_alarm"},
        headers=headers,
    )
    assert res2.status_code == 200
    assert res2.json()["review_status"] == "false_alarm"

    # Invalid review status rejected
    res_bad = client.patch(
        f"/api/alerts/{a1}/review",
        json={"review_status": "invalid_status"},
        headers=headers,
    )
    assert res_bad.status_code == 400

    # Check false alarm rate endpoint
    stats_res = client.get("/api/alerts/stats/false-alarm-rate", headers=headers)
    assert stats_res.status_code == 200
    stats = stats_res.json()
    assert stats["total_reviewed"] == 2
    assert stats["false_alarms"] == 1
    assert stats["false_alarm_rate"] == 0.5


def test_evidence_delivery_and_path_traversal_protection(test_env: dict) -> None:
    """Verify evidence file delivery and rejection of path traversal attempts."""
    client: TestClient = test_env["client"]
    api_token = test_env["api_token"]
    db: AlertDatabaseManager = test_env["db"]
    alerts_dir: Path = test_env["alerts_dir"]
    headers = {"Authorization": f"Bearer {api_token}"}

    # Create legitimate snapshot inside alerts_dir
    legit_snap = alerts_dir / "valid_snap.jpg"
    legit_snap.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 30)

    aid = db.insert_alert(
        timestamp="2026-10-11T01:00:00Z",
        camera_id="CAM-SNAP",
        track_id=88,
        object_class="backpack",
        event_duration=15.0,
        reason="Evidence test",
        snapshot_path=str(legit_snap),
    )

    # 1. Successful fetch with Bearer token
    res_snap = client.get(f"/api/alerts/{aid}/snapshot", headers=headers)
    assert res_snap.status_code == 200
    assert res_snap.headers["content-type"] == "image/jpeg"

    # 2. Successful fetch with query token (used by <img> tags in UI)
    res_query = client.get(f"/api/alerts/{aid}/snapshot?token={api_token}")
    assert res_query.status_code == 200

    # 3. Path Traversal Attack: Alert record pointing to file outside permitted dir
    outside_file = test_env["tmp_path"] / "secret_system_file.txt"
    outside_file.write_text("SENSITIVE DATA")

    evil_aid = db.insert_alert(
        timestamp="2026-10-11T01:00:00Z",
        camera_id="CAM-EVIL",
        track_id=999,
        object_class="backpack",
        event_duration=15.0,
        reason="Traversal attempt",
        snapshot_path=str(outside_file),
    )

    res_traversal = client.get(f"/api/alerts/{evil_aid}/snapshot", headers=headers)
    assert res_traversal.status_code == 403
    assert "Access forbidden" in res_traversal.json()["detail"]
