import os
import sys

# Add backend directory to sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import pytest
from fastapi.testclient import TestClient

# Ensure dev bypass is enabled for tests
os.environ["ALLOW_DEV_AUTH_BYPASS"] = "true"
os.environ["MODEL_PATH"] = os.path.join(backend_dir, "models", "railsafe_rf_model.pkl")

from app.main import app
from app.services.model_service import model_service

client = TestClient(app)

def test_health_check():
    """Verifies that /health returns 200, reports model_loaded=True, and lists expected features."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["model_loaded"] is True
    assert data["model_version"] == "1.0.0"
    assert data["features"] == ["mq2_raw", "mq4_raw", "mq7_raw"]

def test_model_service_direct_inference():
    """Verifies that model_service executes predictions matching Scikit-Learn training."""
    assert model_service.is_loaded

    # Calibrated nominal ambient readings
    nominal_res = model_service.predict(mq2=700.0, mq4=1000.0, mq7=80.0)
    assert nominal_res["prediction"] == "nominal"
    assert nominal_res["label"] == "normal_synthetic"
    assert nominal_res["anomalyScore"] < 0.10
    assert nominal_res["reviewRequired"] is False

    # Elevated anomaly readings
    anomaly_res = model_service.predict(mq2=100.0, mq4=100.0, mq7=100.0)
    assert anomaly_res["prediction"] == "anomaly"
    assert anomaly_res["label"] == "anomaly_synthetic"
    assert anomaly_res["anomalyScore"] > 0.90
    assert anomaly_res["reviewRequired"] is True

def test_predict_endpoint_authenticated_nominal():
    """Verifies successful POST /predict request for nominal baseline."""
    payload = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 142,
        "timestamp": "2026-10-10T10:00:00Z",
        "sensors": {
            "mq2_raw": 700.0,
            "mq4_raw": 1000.0,
            "mq7_raw": 80.0
        }
    }
    headers = {"Authorization": "Bearer DEMO_OFFICER_TOKEN"}
    response = client.post("/predict", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["deviceId"] == "RAILSAFE-ESP32-01"
    assert data["sequence"] == 142
    assert data["prediction"] == "nominal"
    assert data["reviewRequired"] is False
    assert data["userId"] == "demo-officer-NDLS"
    assert "inferenceTimestamp" in data

def test_predict_endpoint_authenticated_anomaly():
    """Verifies successful POST /predict request for anomaly detection."""
    payload = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 143,
        "timestamp": "2026-10-10T10:00:01Z",
        "sensors": {
            "mq2_raw": 100.0,
            "mq4_raw": 100.0,
            "mq7_raw": 100.0
        }
    }
    headers = {"Authorization": "Bearer DEMO_OFFICER_TOKEN"}
    response = client.post("/predict", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["prediction"] == "anomaly"
    assert data["reviewRequired"] is True
    assert data["anomalyScore"] > 0.90

def test_predict_endpoint_missing_token():
    """Verifies that requests without Authorization header are rejected with 401."""
    payload = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 10,
        "timestamp": "2026-10-10T10:00:00Z",
        "sensors": {
            "mq2_raw": 700.0,
            "mq4_raw": 1000.0,
            "mq7_raw": 80.0
        }
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 401
    assert "Missing Authorization header" in response.json()["detail"]

def test_predict_endpoint_invalid_token():
    """Verifies that malformed or unauthorized tokens are rejected."""
    payload = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 10,
        "timestamp": "2026-10-10T10:00:00Z",
        "sensors": {
            "mq2_raw": 700.0,
            "mq4_raw": 1000.0,
            "mq7_raw": 80.0
        }
    }
    headers = {"Authorization": "Bearer BAD_EXPIRED_OR_FORGED_TOKEN"}
    response = client.post("/predict", json=payload, headers=headers)
    assert response.status_code == 401

def test_predict_endpoint_input_validation():
    """Verifies that invalid or out-of-bounds sensor inputs are rejected with 422."""
    headers = {"Authorization": "Bearer DEMO_OFFICER_TOKEN"}

    # Missing mq7_raw
    incomplete_payload = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "timestamp": "2026-10-10T10:00:00Z",
        "sensors": {
            "mq2_raw": 700.0,
            "mq4_raw": 1000.0
        }
    }
    res = client.post("/predict", json=incomplete_payload, headers=headers)
    assert res.status_code == 422

    # Negative sensor value
    negative_payload = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "timestamp": "2026-10-10T10:00:00Z",
        "sensors": {
            "mq2_raw": -50.0,
            "mq4_raw": 1000.0,
            "mq7_raw": 80.0
        }
    }
    res2 = client.post("/predict", json=negative_payload, headers=headers)
    assert res2.status_code == 422
