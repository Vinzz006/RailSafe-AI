"""
Comprehensive Test Suite for Railway Luggage Detection & Anomaly Screening System.
Validates detector, tracker state machine, proximity heuristics, and alert logging.
"""

import os
import sys
import time
import pytest
import numpy as np

# Add project directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from config import (
    STATUS_NORMAL,
    STATUS_ISOLATED,
    STATUS_UNATTENDED,
    UNATTENDED_TIME_THRESHOLD_SEC,
    PROXIMITY_DISTANCE_PX,
)
from detector import LuggageDetector, Detection
from tracker import UnattendedLuggageTracker, LuggageAlertEvent
from alerts import AlertManager


@pytest.fixture
def detector():
    return LuggageDetector()


@pytest.fixture
def tracker():
    return UnattendedLuggageTracker(
        unattended_time_threshold=5.0,  # 5 seconds for rapid testing
        proximity_distance_px=100.0,
        alert_cooldown_sec=10.0,
    )


@pytest.fixture
def alert_manager(tmp_path):
    db_file = tmp_path / "test_alerts.db"
    csv_file = tmp_path / "test_alerts.csv"
    return AlertManager(db_path=db_file, csv_path=csv_file)


def test_detector_initialization(detector):
    """Verifies that YOLO detector initializes properly and is ready."""
    assert detector.is_ready is True
    assert detector.model is not None


def test_detection_on_dummy_frame(detector):
    """Verifies inference runs on blank frame without exceptions."""
    blank_frame = np.zeros((480, 640, 3), dtype=np.uint8)
    persons, luggage = detector.detect_and_track(blank_frame)
    assert isinstance(persons, list)
    assert isinstance(luggage, list)


def test_tracker_accompanied_luggage(tracker):
    """Verifies that a bag with a nearby person remains in STATUS_NORMAL."""
    t0 = 1000.0

    # Bag at (200, 200)
    bag = Detection(
        box=(180, 180, 220, 220),
        confidence=0.85,
        class_id=24,
        class_name="Backpack",
        track_id=1,
        center=(200.0, 200.0),
        is_luggage=True,
    )

    # Person right next to the bag at (220, 200) -> distance ~ 0 px (inside box)
    person = Detection(
        box=(210, 100, 270, 300),
        confidence=0.90,
        class_id=0,
        class_name="Person",
        track_id=10,
        center=(240.0, 200.0),
        is_luggage=False,
    )

    tracked_bags, alerts = tracker.update([bag], [person], current_time=t0)
    assert len(tracked_bags) == 1
    assert tracked_bags[0].status == STATUS_NORMAL
    assert tracked_bags[0].is_alert_active is False
    assert len(alerts) == 0


def test_tracker_unattended_luggage_transition(tracker):
    """
    Verifies that an isolated bag transitions from NORMAL -> ISOLATED -> UNATTENDED
    once the time threshold (5.0s in fixture) is exceeded.
    """
    t0 = 1000.0

    # Bag at (100, 100)
    bag = Detection(
        box=(80, 80, 120, 120),
        confidence=0.88,
        class_id=28,
        class_name="Suitcase",
        track_id=2,
        center=(100.0, 100.0),
        is_luggage=True,
    )

    # Person very far away at (500, 500) -> distance > 100 px
    person = Detection(
        box=(480, 400, 520, 600),
        confidence=0.92,
        class_id=0,
        class_name="Person",
        track_id=11,
        center=(500.0, 500.0),
        is_luggage=False,
    )

    # Initial frame at t0: timer starts
    tracked_bags, alerts = tracker.update([bag], [person], current_time=t0)
    assert tracked_bags[0].status == STATUS_NORMAL
    assert len(alerts) == 0

    # Frame at t0 + 4.1s (exceeds warning threshold of 4.0s)
    tracked_bags, alerts = tracker.update([bag], [person], current_time=t0 + 4.1)
    assert tracked_bags[0].status == STATUS_ISOLATED
    assert len(alerts) == 0

    # Frame at t0 + 5.5s (exceeds unattended threshold of 5.0s)
    tracked_bags, alerts = tracker.update([bag], [person], current_time=t0 + 5.5)
    assert tracked_bags[0].status == STATUS_UNATTENDED
    assert tracked_bags[0].is_alert_active is True
    assert len(alerts) == 1
    assert alerts[0].track_id == 2
    assert alerts[0].class_name == "Suitcase"


def test_tracker_cooldown_prevents_duplicate_alerts(tracker):
    """Verifies that the same unattended bag does NOT emit repeated alerts on consecutive frames."""
    t0 = 1000.0
    bag = Detection(
        box=(80, 80, 120, 120),
        confidence=0.88,
        class_id=24,
        class_name="Backpack",
        track_id=3,
        center=(100.0, 100.0),
        is_luggage=True,
    )

    # Isolated bag exceeds 5.0s threshold
    tracker.update([bag], [], current_time=t0)
    _, alerts1 = tracker.update([bag], [], current_time=t0 + 5.5)
    assert len(alerts1) == 1

    # Next frame 0.1s later: should be suppressed by cooldown (10.0s)
    _, alerts2 = tracker.update([bag], [], current_time=t0 + 5.6)
    assert len(alerts2) == 0


def test_tracker_acknowledgment(tracker):
    """Verifies that acknowledging an alert dismisses the active alert state."""
    t0 = 1000.0
    bag = Detection(
        box=(80, 80, 120, 120),
        confidence=0.88,
        class_id=24,
        class_name="Backpack",
        track_id=4,
        center=(100.0, 100.0),
        is_luggage=True,
    )

    tracker.update([bag], [], current_time=t0)
    tracked_bags, _ = tracker.update([bag], [], current_time=t0 + 6.0)
    assert tracked_bags[0].is_alert_active is True

    # Acknowledge
    tracker.acknowledge_alert(track_id=4)
    assert tracker.tracks[4].acknowledged is True
    assert tracker.tracks[4].is_alert_active is False


def test_alert_manager_logging_and_snapshot(alert_manager):
    """Verifies logging to SQLite, CSV, and snapshot saving."""
    dummy_frame = np.full((480, 640, 3), 120, dtype=np.uint8)
    event = LuggageAlertEvent(
        track_id=5,
        class_name="Backpack",
        confidence=0.91,
        isolation_duration=12.5,
        box=(100, 100, 200, 200),
        center=(150.0, 150.0),
        distance_to_person=250.0,
        timestamp=time.time(),
        status=STATUS_UNATTENDED,
    )

    result = alert_manager.log_alert(event, frame=dummy_frame)
    assert result["id"] > 0
    assert result["track_id"] == 5
    assert os.path.exists(result["snapshot_path"])

    # Query recent alerts
    recent = alert_manager.get_recent_alerts(limit=5)
    assert len(recent) == 1
    assert recent[0]["track_id"] == 5
    assert recent[0]["object_class"] == "Backpack"
