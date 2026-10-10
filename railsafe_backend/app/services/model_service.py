import os
import pickle
import logging
from typing import Dict, Any, List
import numpy as np
import pandas as pd

logger = logging.getLogger("railsafe_backend.model_service")

class ModelService:
    def __init__(self, model_path: str = "models/railsafe_rf_model.pkl", version: str = "1.0.0"):
        self.model_path = model_path
        self.model_version = version
        self.model = None
        self.expected_features: List[str] = ["mq2_raw", "mq4_raw", "mq7_raw"]
        self.classes: List[str] = ["anomaly_synthetic", "normal_synthetic"]
        self.model_name = "RandomForestClassifier (100 Trees - MQ Multi-Sensor)"
        self._load_model()

    def _load_model(self):
        # Check alternative model paths if relative path doesn't match
        candidates = [
            self.model_path,
            os.path.join(os.path.dirname(__file__), "..", "..", self.model_path),
            os.path.join(os.path.dirname(__file__), "..", "..", "models", "railsafe_rf_model.pkl"),
            os.path.join(os.path.dirname(__file__), "..", "..", "models", "trained_model.joblib"),
            "railsafe_backend/models/railsafe_rf_model.pkl",
        ]

        found_path = None
        for p in candidates:
            if os.path.exists(p):
                found_path = p
                break

        if not found_path:
            logger.error(f"Model file not found at any candidate paths: {candidates}")
            return

        try:
            with open(found_path, "rb") as f:
                self.model = pickle.load(f)
            
            # Verify feature contract
            if hasattr(self.model, "feature_names_in_"):
                self.expected_features = list(self.model.feature_names_in_)
            
            if hasattr(self.model, "classes_"):
                self.classes = list(self.model.classes_)
                
            logger.info(
                f"Model successfully loaded from {found_path}. "
                f"Features: {self.expected_features}, Classes: {self.classes}"
            )
        except Exception as e:
            logger.error(f"Failed to load model from {found_path}: {e}")
            self.model = None

    @property
    def is_loaded(self) -> bool:
        return self.model is not None

    def predict(self, mq2: float, mq4: float, mq7: float) -> Dict[str, Any]:
        """
        Executes inference against the trained Random Forest model.
        Features are strictly fed in training order: ['mq2_raw', 'mq4_raw', 'mq7_raw'].
        """
        if not self.is_loaded:
            raise RuntimeError("Machine learning model is not loaded on backend server.")

        # Ensure exact input shape and feature order with named columns
        feature_df = pd.DataFrame(
            [[mq2, mq4, mq7]],
            columns=self.expected_features,
            dtype=np.float64,
        )

        try:
            # Predict probabilities: [P(anomaly_synthetic), P(normal_synthetic)]
            probs = self.model.predict_proba(feature_df)[0]
            
            anomaly_prob = float(probs[0])
            normal_prob = float(probs[1])
            
            is_anomaly = anomaly_prob >= 0.5
            prediction = "anomaly" if is_anomaly else "nominal"
            raw_label = "anomaly_synthetic" if is_anomaly else "normal_synthetic"
            confidence = float(max(anomaly_prob, normal_prob) * 100.0)

            return {
                "prediction": prediction,
                "label": raw_label,
                "anomalyScore": round(anomaly_prob, 4),
                "normalScore": round(normal_prob, 4),
                "confidence": round(confidence, 1),
                "reviewRequired": is_anomaly,
                "modelVersion": self.model_version,
                "inputFeatures": {
                    "mq2_raw": mq2,
                    "mq4_raw": mq4,
                    "mq7_raw": mq7,
                }
            }
        except Exception as e:
            logger.error(f"Inference computation error: {e}")
            raise RuntimeError(f"Model prediction failed: {e}")

# Global singleton instance
model_service = ModelService()
