from typing import Any, Dict, List, Optional, Union
from pydantic import BaseModel, Field, field_validator
from datetime import datetime

class SensorReadingChannel(BaseModel):
    value: float
    unit: Optional[str] = "raw"
    label: Optional[str] = None

def extract_channel_value(v: Any) -> float:
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, dict) and "value" in v:
        val = v["value"]
        if isinstance(val, (int, float)):
            return float(val)
        return float(val)
    raise ValueError(f"Invalid sensor channel format: {v}")

class SensorPayload(BaseModel):
    mq2_raw: float = Field(..., description="MQ-2 Combustible Gas/Smoke sensor reading")
    mq4_raw: float = Field(..., description="MQ-4 Natural Gas/Methane sensor reading")
    mq7_raw: float = Field(..., description="MQ-7 Carbon Monoxide sensor reading")

    @field_validator("mq2_raw", "mq4_raw", "mq7_raw", mode="before")
    @classmethod
    def parse_sensor_value(cls, v: Any) -> float:
        val = extract_channel_value(v)
        if val < 0.0 or val > 100000.0:
            raise ValueError(f"Sensor value {val} out of physically reasonable bounds (0 - 100000)")
        return val

class PredictionRequest(BaseModel):
    deviceId: str = Field(..., min_length=1, max_length=100, description="Hardware Device ID")
    sequence: int = Field(..., ge=0, description="Packet sequence number")
    timestamp: str = Field(..., description="ISO-8601 formatted timestamp")
    sensors: SensorPayload

    @field_validator("timestamp")
    @classmethod
    def validate_timestamp(cls, v: str) -> str:
        try:
            # Validate ISO 8601 format
            datetime.fromisoformat(v.replace("Z", "+00:00"))
            return v
        except Exception:
            raise ValueError("Timestamp must be valid ISO-8601 format (e.g., '2026-10-10T10:00:00Z')")

class PredictionResponse(BaseModel):
    deviceId: str
    sequence: int
    prediction: str = Field(..., description="'anomaly' or 'nominal'")
    label: str = Field(..., description="Raw model class: 'anomaly_synthetic' or 'normal_synthetic'")
    anomalyScore: float = Field(..., description="Calibrated anomaly probability [0.0, 1.0]")
    normalScore: float = Field(..., description="Normal baseline probability [0.0, 1.0]")
    confidence: float = Field(..., description="Confidence percentage [0 - 100]")
    reviewRequired: bool = Field(..., description="Whether secondary protocol inspection is advised")
    modelVersion: str
    inferenceTimestamp: str
    inputFeatures: Dict[str, float]
    userId: Optional[str] = None

class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    model_version: str
    model_name: str
    features: List[str]
