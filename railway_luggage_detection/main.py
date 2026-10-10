"""
Real-Time Computer Vision Luggage Screening Application.
Railway Security & Unattended Baggage Monitoring.
SIH 2026, Problem Statement #26026.
"""

import sys
import time
import argparse
import logging
from typing import Optional, Tuple
import cv2
import numpy as np

from config import (
    DEFAULT_CAMERA_INDEX,
    FALLBACK_CAMERA_INDEX,
    FRAME_WIDTH,
    FRAME_HEIGHT,
    DEFAULT_CONFIDENCE_THRESHOLD,
    STATUS_NORMAL,
    STATUS_ISOLATED,
    STATUS_UNATTENDED,
    STATUS_UNCERTAIN,
    DISCLAIMER_TEXT,
    UNATTENDED_TIME_THRESHOLD_SEC,
)
from detector import LuggageDetector
from tracker import UnattendedLuggageTracker, TrackedLuggage
from alerts import AlertManager

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("railway_luggage.main")


class SecurityHUDApp:
    def __init__(
        self,
        camera_index: int = DEFAULT_CAMERA_INDEX,
        confidence_threshold: float = DEFAULT_CONFIDENCE_THRESHOLD,
    ):
        self.camera_index = camera_index
        self.confidence_threshold = confidence_threshold
        self.detector = LuggageDetector()
        self.tracker = UnattendedLuggageTracker()
        self.alert_manager = AlertManager()

        self.cap: Optional[cv2.VideoCapture] = None
        self.is_running = False
        self.fps = 0.0
        self.total_alerts_count = 0
        self.latest_alert_msg = "System Nominal — Scanning active"
        self.hud_status_color = (0, 230, 118)  # Safe Green

    def open_camera(self, index: int) -> bool:
        """Attempts to open video capture device with target resolutions."""
        if self.cap is not None:
            self.cap.release()

        logger.info(f"Opening video capture device index: {index}...")
        
        # On Windows, using DSHOW backend can improve webcam initialization speed
        if sys.platform.startswith("win"):
            self.cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
        else:
            self.cap = cv2.VideoCapture(index)

        if not self.cap.isOpened():
            # Fallback to default backend
            self.cap = cv2.VideoCapture(index)

        if self.cap.isOpened():
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
            self.camera_index = index
            logger.info(f"Successfully connected to camera device #{index}")
            return True
        
        logger.warning(f"Could not open camera #{index}")
        return False

    def run(self):
        """Main application capture loop with live HUD overlay."""
        if not self.detector.is_ready:
            print("\n[ERROR] YOLO model failed to load. Check internet or model path.")
            return

        # Attempt primary camera, then fallback
        if not self.open_camera(self.camera_index):
            logger.info(f"Trying fallback camera index {FALLBACK_CAMERA_INDEX}...")
            if not self.open_camera(FALLBACK_CAMERA_INDEX):
                print(f"\n[ERROR] Unable to open USB Webcam at index {self.camera_index} or {FALLBACK_CAMERA_INDEX}.")
                print("Troubleshooting steps:")
                print(" 1. Ensure Zebronics ZEB-CRYSTAL PRO USB cable is securely connected.")
                print(" 2. Verify Windows Camera Privacy settings permit desktop app access.")
                print(" 3. Pass explicit camera index: python main.py --camera 1\n")
                return

        self.is_running = True
        window_name = "RailSafe AI — Railway Luggage Screening HUD (SIH 2026)"
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, 960, 720)

        prev_time = time.time()
        frame_count = 0

        print("\n" + "=" * 65)
        print("  RailSafe AI — Luggage Screening & Unattended Anomaly Monitor")
        print("  SIH 2026, Problem Statement #26026 (Indian Railways)")
        print("=" * 65)
        print(" Controls:")
        print("  [Q] or [ESC] : Quit application")
        print("  [A]          : Acknowledge / dismiss active alerts")
        print("  [S]          : Save manual inspection snapshot")
        print("  [C]          : Switch camera index (0 <-> 1)")
        print("  [+] / [-]    : Adjust detection confidence threshold")
        print("=" * 65 + "\n")

        try:
            while self.is_running:
                ret, frame = self.cap.read()
                if not ret or frame is None:
                    logger.warning("Camera frame dropped or disconnected.")
                    time.sleep(0.1)
                    continue

                curr_time = time.time()
                frame_count += 1
                dt = curr_time - prev_time
                if dt >= 0.5:
                    self.fps = frame_count / dt
                    frame_count = 0
                    prev_time = curr_time

                # 1. Detection and Tracking
                persons, luggage = self.detector.detect_and_track(
                    frame=frame,
                    confidence_threshold=self.confidence_threshold,
                )

                # 2. Unattended Luggage Proximity Analysis
                tracked_bags, new_alerts = self.tracker.update(
                    detected_luggage=luggage,
                    detected_persons=persons,
                    current_time=curr_time,
                )

                # 3. Log alerts and save snapshots
                for alert in new_alerts:
                    self.total_alerts_count += 1
                    self.latest_alert_msg = (
                        f"REVIEW REQUIRED: Bag #{alert.track_id} unattended for {alert.isolation_duration}s!"
                    )
                    self.alert_manager.log_alert(alert, frame=frame)
                    logger.warning(f"ALERT: Track #{alert.track_id} ({alert.class_name}) unattended for {alert.isolation_duration}s")

                # 4. Render High-Tech Security HUD
                display_frame = self._render_hud(
                    frame=frame,
                    persons=persons,
                    tracked_bags=tracked_bags,
                    curr_time=curr_time,
                )

                cv2.imshow(window_name, display_frame)

                # Keyboard handling
                key = cv2.waitKey(1) & 0xFF
                if key in (ord('q'), ord('Q'), 27):  # Q or ESC
                    break
                elif key in (ord('a'), ord('A')):
                    self.tracker.reset_acknowledgments()
                    self.latest_alert_msg = "Alerts acknowledged by operator."
                    logger.info("Operator acknowledged all active alerts.")
                elif key in (ord('s'), ord('S')):
                    path = self.alert_manager.save_manual_snapshot(frame, tag="operator_inspect")
                    self.latest_alert_msg = f"Snapshot saved: {path}"
                    logger.info(f"Manual snapshot saved: {path}")
                elif key in (ord('c'), ord('C')):
                    next_idx = 1 if self.camera_index == 0 else 0
                    self.open_camera(next_idx)
                elif key in (ord('+'), ord('=')):
                    self.confidence_threshold = min(0.95, round(self.confidence_threshold + 0.05, 2))
                    logger.info(f"Confidence threshold increased: {self.confidence_threshold}")
                elif key in (ord('-'), ord('_')):
                    self.confidence_threshold = max(0.15, round(self.confidence_threshold - 0.05, 2))
                    logger.info(f"Confidence threshold decreased: {self.confidence_threshold}")

        except KeyboardInterrupt:
            logger.info("Termination signal received.")
        finally:
            self._cleanup()

    def _render_hud(
        self,
        frame: np.ndarray,
        persons: list,
        tracked_bags: list,
        curr_time: float,
    ) -> np.ndarray:
        """Draws bounding boxes, proximity vectors, metric cards, and security status."""
        h, w, _ = frame.shape
        out = frame.copy()

        has_unattended_alert = any(b.status == STATUS_UNATTENDED and not b.acknowledged for b in tracked_bags)
        hud_color = (0, 0, 255) if has_unattended_alert else (0, 230, 118)

        # Draw Person Bounding Boxes
        for p in persons:
            x1, y1, x2, y2 = p.box
            cv2.rectangle(out, (x1, y1), (x2, y2), (0, 230, 118), 2)
            label = f"Person ({int(p.confidence * 100)}%)"
            self._draw_box_header(out, x1, y1, label, (0, 230, 118))

        # Draw Luggage Bounding Boxes & Proximity Indicators
        for bag in tracked_bags:
            x1, y1, x2, y2 = bag.box
            status = bag.status

            if status == STATUS_UNATTENDED:
                box_color = (0, 0, 255)  # Red Alert
                # Pulsing border effect
                pulse = int(abs(np.sin(curr_time * 5.0)) * 2) + 2
                cv2.rectangle(out, (x1, y1), (x2, y2), box_color, pulse)
                label = f"! UNATTENDED ! #{bag.track_id} ({int(bag.isolation_duration)}s)"
            elif status == STATUS_ISOLATED:
                box_color = (0, 190, 255)  # Amber Warning
                cv2.rectangle(out, (x1, y1), (x2, y2), box_color, 2)
                remaining = max(0.0, UNATTENDED_TIME_THRESHOLD_SEC - bag.isolation_duration)
                label = f"Isolated #{bag.track_id} ({int(bag.isolation_duration)}s | Alert in {remaining:.1f}s)"
            elif status == STATUS_UNCERTAIN:
                box_color = (180, 180, 180)  # Grey Uncertain
                cv2.rectangle(out, (x1, y1), (x2, y2), box_color, 1)
                label = f"Moving Bag #{bag.track_id} (Uncertain)"
            else:
                box_color = (255, 140, 0)  # Cyan/Blue Normal
                cv2.rectangle(out, (x1, y1), (x2, y2), box_color, 2)
                label = f"#{bag.track_id} {bag.class_name} (Accompanied)"

            self._draw_box_header(out, x1, y1, label, box_color)

            # Draw proximity vector to nearest person if in isolated/warning stage
            if status in (STATUS_ISOLATED, STATUS_NORMAL) and bag.distance_to_person < 300:
                # Find nearest person center
                if persons:
                    closest_person = min(
                        persons,
                        key=lambda p: np.hypot(bag.center[0] - p.center[0], bag.center[1] - p.center[1]),
                    )
                    bx, by = int(bag.center[0]), int(bag.center[1])
                    px, py = int(closest_person.center[0]), int(closest_person.center[1])
                    cv2.line(out, (bx, by), (px, py), (100, 255, 100), 1, cv2.LINE_AA)

        # Top Security HUD Banner (Glassmorphism dark rectangle)
        hud_bg = out.copy()
        cv2.rectangle(hud_bg, (0, 0), (w, 65), (15, 20, 30), -1)
        out = cv2.addWeighted(hud_bg, 0.85, out, 0.15, 0)

        # Title and department header
        cv2.putText(
            out,
            "RAILSAFE AI — LUGGAGE DETECTION & MONITORING",
            (14, 25),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.60,
            (0, 240, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            out,
            "SIH 2026 PS #26026 | Indian Railways Research Prototype",
            (14, 48),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.40,
            (180, 190, 200),
            1,
            cv2.LINE_AA,
        )

        # Metric badges on top right
        status_label = "ALERT ACTIVE" if has_unattended_alert else "MONITORING NOMINAL"
        cv2.rectangle(out, (w - 380, 10), (w - 220, 52), (30, 40, 60), -1)
        cv2.putText(
            out,
            f"Bags: {len(tracked_bags)} | Persons: {len(persons)}",
            (w - 370, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.42,
            (240, 240, 240),
            1,
            cv2.LINE_AA,
        )
        cv2.putText(
            out,
            f"FPS: {self.fps:.1f} | Conf: {int(self.confidence_threshold * 100)}%",
            (w - 370, 46),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.38,
            (0, 230, 118),
            1,
            cv2.LINE_AA,
        )

        # Status Badge
        cv2.rectangle(out, (w - 210, 10), (w - 12, 52), (0, 0, 180) if has_unattended_alert else (0, 120, 50), -1)
        cv2.putText(
            out,
            status_label,
            (w - 200, 35),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.46,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )

        # Bottom Ticker Banner
        ticker_bg = out.copy()
        cv2.rectangle(ticker_bg, (0, h - 45), (w, h), (10, 15, 25), -1)
        out = cv2.addWeighted(ticker_bg, 0.85, out, 0.15, 0)

        # Bottom alert text & controls notice
        cv2.putText(
            out,
            f"STATUS: {self.latest_alert_msg}",
            (14, h - 26),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            (0, 220, 255) if not has_unattended_alert else (0, 100, 255),
            1,
            cv2.LINE_AA,
        )
        cv2.putText(
            out,
            "[Q] Quit  [A] Ack Alerts  [S] Snapshot  [+/-] Conf  [C] Camera",
            (14, h - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.35,
            (140, 150, 170),
            1,
            cv2.LINE_AA,
        )

        # Disclaimer banner in corner
        cv2.putText(
            out,
            "NOT AN EXPLOSIVE/NARCOTICS SENSOR - HUMAN REVIEW REQUIRED",
            (w - 430, h - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.33,
            (130, 140, 160),
            1,
            cv2.LINE_AA,
        )

        return out

    def _draw_box_header(self, img: np.ndarray, x1: int, y1: int, label: str, color: Tuple[int, int, int]):
        """Renders solid background banner for bounding box text."""
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = 0.45
        thick = 1
        (tw, th), baseline = cv2.getTextSize(label, font, scale, thick)
        top_y = max(y1 - th - 8, 5)
        cv2.rectangle(img, (x1, top_y), (x1 + tw + 8, top_y + th + 6), color, -1)
        cv2.putText(
            img,
            label,
            (x1 + 4, top_y + th + 1),
            font,
            scale,
            (255, 255, 255) if color != (0, 230, 118) else (0, 0, 0),
            thick,
            cv2.LINE_AA,
        )

    def _cleanup(self):
        """Releases resources and closes window."""
        self.is_running = False
        if self.cap is not None:
            self.cap.release()
        cv2.destroyAllWindows()
        logger.info("Application terminated cleanly.")


def main():
    parser = argparse.ArgumentParser(description="RailSafe AI Luggage Screening Monitor")
    parser.add_argument("--camera", type=int, default=DEFAULT_CAMERA_INDEX, help="USB Webcam device index (default: 0)")
    parser.add_argument("--conf", type=float, default=DEFAULT_CONFIDENCE_THRESHOLD, help="YOLO detection confidence threshold (default: 0.35)")
    args = parser.parse_args()

    app = SecurityHUDApp(camera_index=args.camera, confidence_threshold=args.conf)
    app.run()


if __name__ == "__main__":
    main()
