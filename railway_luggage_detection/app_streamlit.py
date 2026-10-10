"""
Streamlit Web Monitoring Dashboard for Railway Luggage Detection & Anomaly Screening.
SIH 2026, Problem Statement #26026.
Launch with: streamlit run app_streamlit.py
"""

import time
import os
import cv2
import pandas as pd
from PIL import Image
import streamlit as st

from config import (
    DEFAULT_CAMERA_INDEX,
    DEFAULT_CONFIDENCE_THRESHOLD,
    FRAME_WIDTH,
    FRAME_HEIGHT,
    UNATTENDED_TIME_THRESHOLD_SEC,
    PROXIMITY_DISTANCE_PX,
    DISCLAIMER_TEXT,
    STATUS_UNATTENDED,
    STATUS_ISOLATED,
    STATUS_NORMAL,
)
from detector import LuggageDetector
from tracker import UnattendedLuggageTracker
from alerts import AlertManager

# Page Configuration
st.set_page_config(
    page_title="RailSafe AI — Luggage Screening Dashboard",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Custom Styling (Dark Indian Railways Security Theme)
st.markdown(
    """
    <style>
    .main { background-color: #0c101c; color: #f1f5f9; }
    .stMetric { background-color: #162035; padding: 12px; border-radius: 10px; border: 1px solid #233454; }
    .alert-banner { background-color: #7f1d1d; border-left: 6px solid #ef4444; padding: 12px; border-radius: 8px; margin-bottom: 12px; }
    .safe-banner { background-color: #064e3b; border-left: 6px solid #10b981; padding: 12px; border-radius: 8px; margin-bottom: 12px; }
    .disclaimer-box { background-color: #1e293b; border: 1px solid #334155; padding: 10px; border-radius: 8px; font-size: 11px; color: #94a3b8; margin-top: 15px; }
    </style>
    """,
    unsafe_allow_html=True,
)


@st.cache_resource
def load_detector():
    return LuggageDetector()


@st.cache_resource
def load_alert_manager():
    return AlertManager()


detector = load_detector()
alert_manager = load_alert_manager()

# Initialize session state for tracker & controls
if "tracker" not in st.session_state:
    st.session_state.tracker = UnattendedLuggageTracker()
if "is_running" not in st.session_state:
    st.session_state.is_running = False

# Sidebar Controls
st.sidebar.image("https://img.icons8.com/color/96/train.png", width=64)
st.sidebar.title("RailSafe AI — Controls")
st.sidebar.caption("Indian Railways Screening Assistance Prototype")

camera_idx = st.sidebar.number_input("USB Webcam Index", min_value=0, max_value=5, value=DEFAULT_CAMERA_INDEX, step=1)
conf_thresh = st.sidebar.slider("Detection Confidence", min_value=0.15, max_value=0.90, value=DEFAULT_CONFIDENCE_THRESHOLD, step=0.05)
time_thresh = st.sidebar.slider("Unattended Time Threshold (s)", min_value=3.0, max_value=30.0, value=UNATTENDED_TIME_THRESHOLD_SEC, step=1.0)
prox_dist = st.sidebar.slider("Proximity Distance (px)", min_value=80.0, max_value=300.0, value=PROXIMITY_DISTANCE_PX, step=10.0)

# Update tracker dynamic thresholds
st.session_state.tracker.time_threshold = time_thresh
st.session_state.tracker.proximity_distance = prox_dist

col_ctrl1, col_ctrl2 = st.sidebar.columns(2)
start_btn = col_ctrl1.button("Start Camera", use_container_width=True, type="primary")
stop_btn = col_ctrl2.button("Stop Camera", use_container_width=True)

if start_btn:
    st.session_state.is_running = True
if stop_btn:
    st.session_state.is_running = False

if st.sidebar.button("Acknowledge Active Alerts", use_container_width=True):
    st.session_state.tracker.reset_acknowledgments()
    st.sidebar.success("All active alerts acknowledged.")

st.sidebar.markdown(f"<div class='disclaimer-box'><b>Disclaimer:</b> {DISCLAIMER_TEXT}</div>", unsafe_allow_html=True)

# Main Dashboard Header
st.title("🛡️ RailSafe AI — Luggage Screening & Anomaly Monitor")
st.caption("SIH 2026 Problem Statement #26026 | Computer Vision Object Tracking & Proximity Intelligence")

# Top Metrics Row
metric_col1, metric_col2, metric_col3, metric_col4, metric_col5 = st.columns(5)
fps_placeholder = metric_col1.empty()
persons_placeholder = metric_col2.empty()
luggage_placeholder = metric_col3.empty()
status_placeholder = metric_col4.empty()
alerts_placeholder = metric_col5.empty()

# Layout: Video Feed and Alerts Feed
vid_col, alert_col = st.columns([7, 5])
frame_placeholder = vid_col.empty()

with alert_col:
    st.subheader("📋 Security Alert Log")
    alert_table_placeholder = st.empty()
    snapshot_placeholder = st.empty()

# Main Video Capture & Processing Loop
if st.session_state.is_running:
    cap = cv2.VideoCapture(camera_idx)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)

    if not cap.isOpened():
        st.error(f"Could not open camera device index #{camera_idx}. Ensure USB webcam is connected and accessible.")
        st.session_state.is_running = False
    else:
        prev_time = time.time()
        fps = 0.0

        while st.session_state.is_running:
            ret, frame = cap.read()
            if not ret or frame is None:
                st.warning("Frame read timeout. Retrying...")
                time.sleep(0.1)
                continue

            curr_time = time.time()
            dt = curr_time - prev_time
            if dt > 0:
                fps = 0.9 * fps + 0.1 * (1.0 / dt) if fps > 0 else (1.0 / dt)
            prev_time = curr_time

            # 1. Detection and Tracking
            persons, luggage = detector.detect_and_track(frame, confidence_threshold=conf_thresh)

            # 2. Unattended Luggage Proximity Assessment
            tracked_bags, new_alerts = st.session_state.tracker.update(
                detected_luggage=luggage,
                detected_persons=persons,
                current_time=curr_time,
            )

            # 3. Log Alerts
            for alert in new_alerts:
                alert_manager.log_alert(alert, frame=frame)

            # 4. Annotate Video Frame
            annotated = frame.copy()
            for p in persons:
                x1, y1, x2, y2 = p.box
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 230, 118), 2)
                cv2.putText(annotated, f"Person ({int(p.confidence*100)}%)", (x1, max(y1 - 6, 15)), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 230, 118), 1)

            has_unattended = False
            for bag in tracked_bags:
                x1, y1, x2, y2 = bag.box
                if bag.status == STATUS_UNATTENDED:
                    has_unattended = True
                    color = (0, 0, 255)
                    label = f"REVIEW ALERT: #{bag.track_id} {bag.class_name} ({int(bag.isolation_duration)}s)"
                elif bag.status == STATUS_ISOLATED:
                    color = (0, 190, 255)
                    label = f"Isolated: #{bag.track_id} ({int(bag.isolation_duration)}s)"
                else:
                    color = (255, 140, 0)
                    label = f"#{bag.track_id} {bag.class_name}"

                cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
                cv2.putText(annotated, label, (x1, max(y1 - 6, 15)), cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, 1)

            # Convert BGR to RGB for Streamlit rendering
            rgb_frame = cv2.cvtColor(annotated, cv2.COLOR_BGR2RGB)
            frame_placeholder.image(rgb_frame, channels="RGB", use_container_width=True)

            # Update Metrics
            fps_placeholder.metric("FPS", f"{fps:.1f}")
            persons_placeholder.metric("Visible Persons", len(persons))
            luggage_placeholder.metric("Visible Luggage", len(tracked_bags))
            status_placeholder.metric("Security Status", "ALERT" if has_unattended else "NOMINAL")
            recent_alerts = alert_manager.get_recent_alerts(limit=5)
            alerts_placeholder.metric("Recorded Alerts", len(recent_alerts))

            # Update Alert Log Table
            if recent_alerts:
                df = pd.DataFrame(recent_alerts)[["timestamp", "track_id", "object_class", "isolation_duration", "status"]]
                df.columns = ["Timestamp", "Track #", "Item", "Duration (s)", "Status"]
                alert_table_placeholder.dataframe(df, use_container_width=True, hide_index=True)

                latest_snap = recent_alerts[0].get("snapshot_path")
                if latest_snap and os.path.exists(latest_snap):
                    snapshot_placeholder.image(latest_snap, caption=f"Latest Snapshot: Track #{recent_alerts[0]['track_id']}", use_container_width=True)

            # Prevent high CPU spinning
            time.sleep(0.01)

        cap.release()
else:
    frame_placeholder.info("Camera inactive. Press **Start Camera** in the sidebar to begin real-time monitoring.")
    recent_alerts = alert_manager.get_recent_alerts(limit=10)
    if recent_alerts:
        df = pd.DataFrame(recent_alerts)[["timestamp", "track_id", "object_class", "isolation_duration", "status"]]
        df.columns = ["Timestamp", "Track #", "Item", "Duration (s)", "Status"]
        alert_table_placeholder.dataframe(df, use_container_width=True, hide_index=True)
    else:
        alert_table_placeholder.write("No alerts recorded yet.")
