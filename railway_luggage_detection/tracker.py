"""
Tracker & Unattended Luggage Analysis Logic.
Analyzes spatial proximity between people and luggage over time.
Flags unattended luggage as a review alert requiring human verification.
"""

import time
import math
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
from detector import Detection
from config import (
    UNATTENDED_TIME_THRESHOLD_SEC,
    ISOLATION_WARNING_SEC,
    PROXIMITY_DISTANCE_PX,
    MAX_STATIONARY_MOVEMENT_PX,
    ALERT_COOLDOWN_SEC,
    STATUS_NORMAL,
    STATUS_ISOLATED,
    STATUS_UNATTENDED,
    STATUS_UNCERTAIN,
)

logger = logging.getLogger("railway_luggage.tracker")


@dataclass
class TrackedLuggage:
    track_id: int
    class_name: str
    confidence: float
    box: Tuple[int, int, int, int]
    center: Tuple[float, float]
    first_seen_time: float
    last_seen_time: float
    initial_position: Tuple[float, float]
    distance_to_person: float = float("inf")
    isolated_since: Optional[float] = None
    isolation_duration: float = 0.0
    status: str = STATUS_NORMAL
    is_alert_active: bool = False
    last_alert_time: float = 0.0
    acknowledged: bool = False
    frames_missed: int = 0


@dataclass
class LuggageAlertEvent:
    track_id: int
    class_name: str
    confidence: float
    isolation_duration: float
    box: Tuple[int, int, int, int]
    center: Tuple[float, float]
    distance_to_person: float
    timestamp: float
    status: str = STATUS_UNATTENDED


class UnattendedLuggageTracker:
    def __init__(
        self,
        unattended_time_threshold: float = UNATTENDED_TIME_THRESHOLD_SEC,
        proximity_distance_px: float = PROXIMITY_DISTANCE_PX,
        alert_cooldown_sec: float = ALERT_COOLDOWN_SEC,
    ):
        self.time_threshold = unattended_time_threshold
        self.proximity_distance = proximity_distance_px
        self.alert_cooldown = alert_cooldown_sec
        self.tracks: Dict[int, TrackedLuggage] = {}
        self._next_synthetic_id = 9000

    def update(
        self,
        detected_luggage: List[Detection],
        detected_persons: List[Detection],
        current_time: Optional[float] = None,
    ) -> Tuple[List[TrackedLuggage], List[LuggageAlertEvent]]:
        """
        Updates bag tracking states, assesses proximity to persons, and flags alerts.
        """
        if current_time is None:
            current_time = time.time()

        new_alerts: List[LuggageAlertEvent] = []
        active_ids = set()

        # Step 1: Update/match luggage detections
        for bag in detected_luggage:
            t_id = bag.track_id
            if t_id is None:
                # Fallback matching based on centroid distance if ByteTrack didn't assign an ID
                t_id = self._match_or_create_synthetic_track(bag.center)

            active_ids.add(t_id)

            if t_id not in self.tracks:
                # Initialize new tracked bag
                self.tracks[t_id] = TrackedLuggage(
                    track_id=t_id,
                    class_name=bag.class_name,
                    confidence=bag.confidence,
                    box=bag.box,
                    center=bag.center,
                    first_seen_time=current_time,
                    last_seen_time=current_time,
                    initial_position=bag.center,
                )
            else:
                # Update existing track
                track = self.tracks[t_id]
                track.box = bag.box
                track.center = bag.center
                track.confidence = bag.confidence
                track.last_seen_time = current_time
                track.frames_missed = 0

        # Step 2: Increment missed frames for unobserved tracks
        for t_id, track in list(self.tracks.items()):
            if t_id not in active_ids:
                track.frames_missed += 1
                # If bag disappeared for > 3.5 seconds, remove tracking history
                if current_time - track.last_seen_time > 3.5:
                    del self.tracks[t_id]

        # Step 3: Compute person-luggage proximity & unattended state
        for t_id, track in self.tracks.items():
            min_dist = float("inf")
            for person in detected_persons:
                dist = self._compute_distance(track.center, person.box, person.center)
                if dist < min_dist:
                    min_dist = dist

            track.distance_to_person = min_dist

            # Verify whether bag has remained approximately stationary
            displacement = math.hypot(
                track.center[0] - track.initial_position[0],
                track.center[1] - track.initial_position[1],
            )
            is_stationary = displacement <= MAX_STATIONARY_MOVEMENT_PX

            if min_dist <= self.proximity_distance:
                # Person is nearby (accompanied)
                track.isolated_since = None
                track.isolation_duration = 0.0
                track.status = STATUS_NORMAL
                track.is_alert_active = False
                # If position moved significantly with person, update reference anchor
                if not is_stationary:
                    track.initial_position = track.center
            else:
                # Person is absent from proximity threshold
                if track.isolated_since is None:
                    track.isolated_since = current_time

                track.isolation_duration = current_time - track.isolated_since

                if not is_stationary:
                    # Bag is moving without an identified person (e.g. carrier occluded or conveyor)
                    track.status = STATUS_UNCERTAIN
                    track.is_alert_active = False
                elif track.isolation_duration >= self.time_threshold:
                    # Threshold exceeded!
                    track.status = STATUS_UNATTENDED
                    track.is_alert_active = not track.acknowledged

                    # Emit alert event if cooldown has elapsed
                    if (
                        not track.acknowledged
                        and (current_time - track.last_alert_time) >= self.alert_cooldown
                    ):
                        track.last_alert_time = current_time
                        new_alerts.append(
                            LuggageAlertEvent(
                                track_id=track.track_id,
                                class_name=track.class_name,
                                confidence=track.confidence,
                                isolation_duration=round(track.isolation_duration, 1),
                                box=track.box,
                                center=track.center,
                                distance_to_person=round(min_dist, 1),
                                timestamp=current_time,
                                status=STATUS_UNATTENDED,
                            )
                        )
                elif track.isolation_duration >= ISOLATION_WARNING_SEC:
                    track.status = STATUS_ISOLATED
                    track.is_alert_active = False
                else:
                    track.status = STATUS_NORMAL
                    track.is_alert_active = False

        return list(self.tracks.values()), new_alerts

    def acknowledge_alert(self, track_id: int):
        """Marks an alert for a specific tracked bag as reviewed/acknowledged."""
        if track_id in self.tracks:
            self.tracks[track_id].acknowledged = True
            self.tracks[track_id].is_alert_active = False
            logger.info(f"Alert acknowledged for bag Track #{track_id}")

    def reset_acknowledgments(self):
        """Resets all acknowledged statuses."""
        for track in self.tracks.values():
            track.acknowledged = False

    def _compute_distance(
        self,
        bag_center: Tuple[float, float],
        person_box: Tuple[int, int, int, int],
        person_center: Tuple[float, float],
    ) -> float:
        """
        Calculates distance from bag centroid to the nearest point on person bounding box.
        """
        bx, by = bag_center
        px1, py1, px2, py2 = person_box

        # Clamping bag center to closest point on person box rectangle
        closest_x = max(px1, min(bx, px2))
        closest_y = max(py1, min(by, py2))

        return math.hypot(bx - closest_x, by - closest_y)

    def _match_or_create_synthetic_track(self, center: Tuple[float, float]) -> int:
        """Fallback spatial association if ByteTrack omits ID."""
        for t_id, track in self.tracks.items():
            dist = math.hypot(center[0] - track.center[0], center[1] - track.center[1])
            if dist < 60.0:
                return t_id
        self._next_synthetic_id += 1
        return self._next_synthetic_id
