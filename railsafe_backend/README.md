# RailSafe AI — Machine Learning Telemetry Screening Backend

A production-ready **Python FastAPI** microservice for **RailSafe AI**. Decoupled from the Flutter mobile app, this service executes authenticated, edge-assisted machine learning inference using a trained **Random Forest Classifier** (`RandomForestClassifier`, 100 decision trees) across MQ-2, MQ-4, and MQ-7 sensor telemetry streams.

---

## 1. System Architecture

```
Physical Sensors (ESP32: MQ-2, MQ-4, MQ-7)
           | BLE Notifications (1 Hz)
           v
Flutter Mobile Application (Android)
           | HTTPS POST /predict (Bearer Firebase ID Token)
           v
FastAPI Backend Server (Cloud Run / Container)
  ├── Firebase Admin SDK Token Verification
  ├── Strict Pydantic Schema Validation
  └── Random Forest Inference (100 Trees)
           | JSON Prediction & Anomaly Score
           v
Flutter Displays Results & Syncs Record to Cloud Firestore
```

---

## 2. API Endpoints

### `GET /health`
Returns server operational health, model readiness, and expected sensor feature contract.

**Response:**
```json
{
  "status": "ok",
  "model_loaded": true,
  "model_version": "1.0.0",
  "model_name": "RandomForestClassifier (100 Trees - MQ Multi-Sensor)",
  "features": ["mq2_raw", "mq4_raw", "mq7_raw"]
}
```

### `POST /predict`
Evaluates authenticated multi-channel sensor packets.

**Headers:**
- `Authorization: Bearer <Firebase_ID_Token>`
- `Content-Type: application/json`

**Request Body:**
```json
{
  "deviceId": "RAILSAFE-ESP32-01",
  "sequence": 142,
  "timestamp": "2026-10-10T10:00:00Z",
  "sensors": {
    "mq2_raw": 700.0,
    "mq4_raw": 1000.0,
    "mq7_raw": 80.0
  }
}
```

**Response Body:**
```json
{
  "deviceId": "RAILSAFE-ESP32-01",
  "sequence": 142,
  "prediction": "nominal",
  "label": "normal_synthetic",
  "anomalyScore": 0.0103,
  "normalScore": 0.9897,
  "confidence": 99.0,
  "reviewRequired": false,
  "modelVersion": "1.0.0",
  "inferenceTimestamp": "2026-10-10T10:00:01.123456+00:00",
  "inputFeatures": {
    "mq2_raw": 700.0,
    "mq4_raw": 1000.0,
    "mq7_raw": 80.0
  },
  "userId": "firebase-officer-uid"
}
```

---

## 3. Local Development Setup

### Prerequisites
- Python 3.10+ (Python 3.11/3.13 supported)
- pip

### 1. Install Dependencies
```bash
cd railsafe_backend
pip install -r requirements.txt
```

### 2. Configure Environment
Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

Key environment settings:
- `ALLOW_DEV_AUTH_BYPASS=true`: Allows demo inspection token (`DEMO_OFFICER_TOKEN`) for offline testing.
- `FIREBASE_PROJECT_ID=railsafe-ai`: Your Firebase project ID.
- `MODEL_PATH=models/railsafe_rf_model.pkl`: Path to trained model.

### 3. Run Locally with Uvicorn
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Interactive OpenAPI Swagger UI is available at:
`http://localhost:8000/docs`

### 4. Run Automated Tests
```bash
pytest tests/ -v
```

---

## 4. Google Cloud Run Deployment

Deploy containerized backend to Google Cloud Run:

```bash
# 1. Authenticate with Google Cloud
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# 2. Build and deploy container directly
gcloud run deploy railsafe-backend \
  --source . \
  --platform managed \
  --region asia-south1 \
  --allow-unauthenticated \
  --set-env-vars ENVIRONMENT=production,ALLOW_DEV_AUTH_BYPASS=false,MODEL_PATH=models/railsafe_rf_model.pkl
```

Once deployed, Google Cloud Run returns a secure HTTPS URL:
`https://railsafe-backend-xyz.a.run.app`

---

## 5. Flutter App Connection

In the RailSafe AI Android application:
1. Open **Settings & Profile**.
2. Under **Backend Server Configuration**, enter:
   - For Android Emulator: `http://10.0.2.2:8000`
   - For Physical Device on Local Wi-Fi: `http://<YOUR_LOCAL_IP>:8000`
   - For Cloud Run Production: `https://railsafe-backend-xyz.a.run.app`
3. Tap **Test Server Connection** to verify health and latency.
