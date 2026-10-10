"""
Detector module wrapping Ultralytics YOLO with tracking capabilities.
Identifies people, backpacks, handbags, and suitcases.
"""

import logging
from dataclasses import dataclass
from typing import List, Tuple, Optional
import numpy as np
from ultralytics import YOLO

from config import (
    MODEL_PATH,
    PERSON_CLASS_IDS,
    LUGGAGE_CLASS_IDS,
    CLASS_DISPLAY_NAMES,
    DEFAULT_CONFIDENCE_THRESHOLD,
    DEFAULT_IOU_THRESHOLD,
)

logger = logging.getLogger("railway_luggage.detector")


@dataclass
class Detection:
    box: Tuple[int, int, int, int]  # (x1, y1, x2, y2)
    confidence: float
    class_id: int
    class_name: str
    track_id: Optional[int]
    center: Tuple[float, float]     # (cx, cy)
    is_luggage: bool


class LuggageDetector:
    def __init__(self, model_path: str = MODEL_PATH):
        self.model_path = model_path
        self.model: Optional[YOLO] = None
        self.is_ready = False
        self._load_model()

    def _load_model(self):
        try:
            logger.info(f"Loading YOLO model from: {self.model_path}")
            self.model = YOLO(self.model_path)
            self.is_ready = True
            logger.info(f"YOLO model ready. Loaded {len(self.model.names)} COCO classes.")
        except Exception as e:
            logger.error(f"Failed to initialize YOLO model from '{self.model_path}': {e}")
            self.model = None
            self.is_ready = False

    def detect_and_track(
        self,
        frame: np.ndarray,
        confidence_threshold: float = DEFAULT_CONFIDENCE_THRESHOLD,
        iou_threshold: float = DEFAULT_IOU_THRESHOLD,
    ) -> Tuple[List[Detection], List[Detection]]:
        """
        Runs object detection and multi-object tracking (ByteTrack) on a frame.
        Returns:
            Tuple of (persons: List[Detection], luggage: List[Detection])
        """
        if not self.is_ready or self.model is None:
            return [], []

        target_classes = PERSON_CLASS_IDS + LUGGAGE_CLASS_IDS

        try:
            # Use ByteTrack tracking mode to maintain track IDs between frames
            results = self.model.track(
                source=frame,
                persist=True,
                conf=confidence_threshold,
                iou=iou_threshold,
                classes=target_classes,
                verbose=False,
            )
        except Exception as e:
            logger.warning(f"Tracking error encountered ({e}), falling back to direct detection.")
            try:
                results = self.model(
                    source=frame,
                    conf=confidence_threshold,
                    iou=iou_threshold,
                    classes=target_classes,
                    verbose=False,
                )
            except Exception as inner_e:
                logger.error(f"Inference failed: {inner_e}")
                return [], []

        if not results or len(results) == 0:
            return [], []

        boxes_data = results[0].boxes
        if boxes_data is None or len(boxes_data) == 0:
            return [], []

        persons: List[Detection] = []
        luggage: List[Detection] = []

        xyxy = boxes_data.xyxy.cpu().numpy()
        confs = boxes_data.conf.cpu().numpy()
        cls_ids = boxes_data.cls.cpu().numpy().astype(int)
        
        # Track IDs may be None if tracker hasn't assigned an ID yet
        track_ids = (
            boxes_data.id.cpu().numpy().astype(int)
            if boxes_data.id is not None
            else [None] * len(xyxy)
        )

        for i in range(len(xyxy)):
            x1, y1, x2, y2 = map(int, xyxy[i])
            conf = float(confs[i])
            c_id = int(cls_ids[i])
            t_id = int(track_ids[i]) if track_ids[i] is not None else None

            cx = (x1 + x2) / 2.0
            cy = (y1 + y2) / 2.0
            c_name = CLASS_DISPLAY_NAMES.get(c_id, self.model.names.get(c_id, f"Class {c_id}"))
            is_lugg = c_id in LUGGAGE_CLASS_IDS

            det = Detection(
                box=(x1, y1, x2, y2),
                confidence=round(conf, 3),
                class_id=c_id,
                class_name=c_name,
                track_id=t_id,
                center=(cx, cy),
                is_luggage=is_lugg,
            )

            if is_lugg:
                luggage.append(det)
            elif c_id in PERSON_CLASS_IDS:
                persons.append(det)

        return persons, luggage
