"""
Configuration module for the Railway Luggage Detection & Anomaly Screening System.
Smart India Hackathon 2026 - Problem Statement #26026
"""

import os
from pathlib import Path

# Base Directories
BASE_DIR = Path(__file__).resolve().parent
LOGS_DIR = BASE_DIR / "logs"
SNAPSHOTS_DIR = BASE_DIR / "snapshots"
MODELS_DIR = BASE_DIR / "models"

# Ensure output directories exist
LOGS_DIR.mkdir(parents=True, exist_ok=True)
SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
MODELS_DIR.mkdir(parents=True, exist_ok=True)

# Database and Log Paths
DB_PATH = LOGS_DIR / "security_alerts.db"
CSV_LOG_PATH = LOGS_DIR / "luggage_alerts.csv"

# Camera Configuration
DEFAULT_CAMERA_INDEX = 0  # Primary USB Webcam (e.g. Zebronics ZEB-CRYSTAL PRO)
FALLBACK_CAMERA_INDEX = 1
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
TARGET_FPS = 30

# Model Configuration
# Check local model paths in order: root, models dir, or download yolov8n.pt / yolo11n.pt
DEFAULT_MODEL_NAME = "yolov8n.pt"
WORKSPACE_ROOT_MODEL = BASE_DIR.parent / "yolov8n.pt"
MODEL_PATH = str(WORKSPACE_ROOT_MODEL if WORKSPACE_ROOT_MODEL.exists() else DEFAULT_MODEL_NAME)

DEFAULT_CONFIDENCE_THRESHOLD = 0.35
DEFAULT_IOU_THRESHOLD = 0.45

# COCO Target Class IDs
# 0: person
# 24: backpack
# 26: handbag
# 28: suitcase
PERSON_CLASS_IDS = [0]
LUGGAGE_CLASS_IDS = [24, 26, 28]

CLASS_DISPLAY_NAMES = {
    0: "Person",
    24: "Backpack",
    26: "Handbag",
    28: "Suitcase",
}

# Unattended Luggage Heuristic Parameters
# Time (in seconds) a bag must remain isolated before raising an alert
UNATTENDED_TIME_THRESHOLD_SEC = 10.0

# Warning warning threshold before full alert (in seconds)
ISOLATION_WARNING_SEC = 4.0

# Pixel distance threshold between bag center and nearest person
# In 640x480 frame, ~150-180 pixels represents a realistic proximity zone
PROXIMITY_DISTANCE_PX = 160.0

# Maximum movement in pixels to consider a bag stationary
MAX_STATIONARY_MOVEMENT_PX = 45.0

# Cooldown between repeated alert logs/snapshots for the same tracked bag (seconds)
ALERT_COOLDOWN_SEC = 15.0

# Status Constants
STATUS_NORMAL = "Normal"
STATUS_ISOLATED = "Isolated — Observation Active"
STATUS_UNATTENDED = "Potentially Unattended — Review Required"
STATUS_UNCERTAIN = "Detection Uncertain"

# Ethical & Scientific Limitations Notice
DISCLAIMER_TEXT = (
    "PROTOTYPE NOTICE: Demonstration system for luggage monitoring and unattended baggage screening. "
    "Alerts require human physical verification. This optical camera system cannot see inside opaque "
    "luggage and is NOT a certified explosive or narcotics detector."
)
