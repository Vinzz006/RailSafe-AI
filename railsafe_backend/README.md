# RailSafe AI — Machine Learning Telemetry Screening Backend
### Production Docker Container & Google Cloud Run Deployment Guide

A production-ready **Python FastAPI** microservice for **RailSafe AI**. Decoupled from the Flutter mobile app, this service executes authenticated, edge-assisted machine learning inference using a trained **Random Forest Classifier** (`RandomForestClassifier`, 100 decision trees) across MQ-2, MQ-4, and MQ-7 sensor telemetry streams.

---

## 1. System Architecture

```
Physical Sensors (ESP32: MQ-2, MQ-4, MQ-7)
           │ BLE Notifications (1 Hz)
           ▼
Flutter Mobile Application (Android)
           │ HTTPS POST /predict (Bearer Firebase ID Token)
           ▼
FastAPI Docker Container (Cloud Run / Local Docker)
  ├── Non-root runtime environment (appuser)
  ├── Firebase Admin SDK Token Verification
  ├── Strict Pydantic Telemetry Range Validation (0 - 100,000)
  ├── Random Forest Inference (100 Trees via Scikit-Learn)
  └── Dynamic Port Binding (${PORT:-8000}) with graceful signal handling
           │ JSON Prediction & Anomaly Score
           ▼
Flutter Displays Results & Syncs Record to Cloud Firestore
```

---

## 2. Directory Structure

```
railsafe_backend/
├── app/
│   ├── api/
│   │   ├── __init__.py
│   │   └── endpoints.py          # /health and /predict route handlers
│   ├── schemas/
│   │   ├── __init__.py
│   │   └── prediction.py         # Pydantic request, response, and health models
│   ├── security/
│   │   ├── __init__.py
│   │   └── firebase_auth.py      # Firebase Admin SDK Bearer token validator
│   ├── services/
│   │   ├── __init__.py
│   │   └── model_service.py      # Scikit-Learn 100-tree model inference engine
│   ├── __init__.py
│   └── main.py                   # FastAPI ASGI entry point (app.main:app)
├── models/
│   ├── railsafe_rf_model.pkl     # Trained Random Forest model binary
│   └── trained_model.joblib      # Secondary joblib serialization artifact
├── tests/
│   └── test_backend.py           # Pytest test suite (7/7 tests passing)
├── .dockerignore                 # Excludes caches, secrets, test artifacts
├── .env.example                  # Environment configuration template
├── Dockerfile                    # Production multi-platform container recipe
├── requirements.txt              # Production Python dependencies
└── README.md                     # Architecture, Docker, and Cloud Run guide
```

---

## 3. API Specification

### `GET /health`
Returns server operational health, model readiness, and expected sensor feature contract.

**Response (HTTP 200):**
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

**Response Body (Nominal Baseline):**
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

**Response Body (Flagged Anomaly Scenario):**
```json
{
  "deviceId": "RAILSAFE-ESP32-01",
  "sequence": 143,
  "prediction": "anomaly",
  "label": "anomaly_synthetic",
  "anomalyScore": 0.99,
  "normalScore": 0.01,
  "confidence": 99.0,
  "reviewRequired": true,
  "modelVersion": "1.0.0",
  "inferenceTimestamp": "2026-10-10T10:00:02.123456+00:00",
  "inputFeatures": {
    "mq2_raw": 100.0,
    "mq4_raw": 100.0,
    "mq7_raw": 100.0
  },
  "userId": "firebase-officer-uid"
}
```

---

## 4. Local Python Setup

### Prerequisites
- Python 3.10+ (Tested on Python 3.11 and 3.13)
- pip

```bash
cd railsafe_backend

# 1. Create virtual environment
python -m venv venv

# Windows PowerShell:
.\venv\Scripts\Activate.ps1
# Linux / macOS:
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Configure environment
cp .env.example .env

# 4. Run tests
pytest tests/ -v

# 5. Start development server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 5. Docker Container Build & Run

### Step 1: Build the Production Docker Image
Run from the `railsafe_backend/` directory:

```bash
docker build -t railsafe-backend:latest .
```

### Step 2: Run the Container Locally

**Using default port 8000 (if port 8000 is free):**
```bash
docker run --rm -d --name railsafe-backend -p 8000:8000 --env-file .env railsafe-backend:latest
```

**Using custom port 8080 (if port 8000 is occupied):**
```bash
docker run --rm -d --name railsafe-backend -e PORT=8080 -p 8080:8080 --env-file .env railsafe-backend:latest
```

### Step 3: Check Container Status & Logs
```bash
docker ps
docker logs railsafe-backend
```

### Step 4: Stop the Container Gracefully
```bash
docker stop railsafe-backend
```

---

## 6. Testing Container Endpoints

You can test the running container via cURL or PowerShell:

### Health Check:
```bash
curl -X GET http://localhost:8000/health
```

### Predict Request (Nominal Sample with Dev Bypass Token):
```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer DEMO_OFFICER_TOKEN" \
  -d '{
    "deviceId": "RAILSAFE-ESP32-01",
    "sequence": 142,
    "timestamp": "2026-10-10T10:00:00Z",
    "sensors": {
      "mq2_raw": 700.0,
      "mq4_raw": 1000.0,
      "mq7_raw": 80.0
    }
  }'
```

### Predict Request (Anomaly Sample):
```bash
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer DEMO_OFFICER_TOKEN" \
  -d '{
    "deviceId": "RAILSAFE-ESP32-01",
    "sequence": 143,
    "timestamp": "2026-10-10T10:00:01Z",
    "sensors": {
      "mq2_raw": 100.0,
      "mq4_raw": 100.0,
      "mq7_raw": 100.0
    }
  }'
```

---

## 7. Firebase Authentication & Security

1. **Bearer Token Authentication:** Every protected endpoint (`/predict`) requires an `Authorization: Bearer <TOKEN>` header.
2. **Production Verification:** The token is validated cryptographically against Google public keys using `firebase_admin.auth.verify_id_token()`. Expired, forged, or missing tokens receive an immediate `HTTP 401 Unauthorized`.
3. **Application Default Credentials (ADC):** When deployed to Google Cloud Run, the container automatically leverages Cloud Run's attached service account identity. No private key files or JSON secrets need to be mounted into the container.
4. **Local Development Bypass:** If running tests without live network access to Firebase, set `ALLOW_DEV_AUTH_BYPASS=true` in `.env` to accept `DEMO_OFFICER_TOKEN`. **This flag must be set to `false` in production.**

---

## 8. Google Cloud Run Deployment

Deploy the containerized microservice to Google Cloud Run:

### Step 1: Install & Initialize Google Cloud SDK
```bash
gcloud auth login
gcloud config set project YOUR_GOOGLE_CLOUD_PROJECT_ID
```

### Step 2: Enable Required Cloud Services
```bash
gcloud services enable run.googleapis.com cloudbuild.googleapis.com
```

### Step 3: Deploy Directly from Source (Recommended)
From inside the `railsafe_backend/` folder:
```bash
gcloud run deploy railsafe-backend \
  --source . \
  --platform managed \
  --region asia-south1 \
  --allow-unauthenticated \
  --set-env-vars ENVIRONMENT=production,ALLOW_DEV_AUTH_BYPASS=false,MODEL_PATH=models/railsafe_rf_model.pkl
```

*Note:* `--allow-unauthenticated` allows incoming mobile app requests to reach the Cloud Run HTTPS endpoint. The endpoint is secured at the application layer by Firebase Bearer Token verification on every protected request.

### Step 4: Retrieve the Deployed HTTPS URL
Once deployment finishes, Google Cloud Run displays the secure HTTPS URL:
`https://railsafe-backend-xxxxxxxxxx.a.run.app`

---

## 9. Configuring the Backend URL in Flutter

In the **RailSafe AI** Flutter mobile app:
1. Open the app and tap the **Settings** icon (gear).
2. Scroll to the **Backend Server Configuration** card.
3. In the **Backend Server URL** field, enter:
   - For Android Emulator connecting to host laptop: `http://10.0.2.2:8000`
   - For Physical Android Phone on same Wi-Fi: `http://<YOUR_LAPTOP_IP>:8000` (e.g. `http://192.168.1.15:8000`)
   - For Deployed Cloud Run Microservice: `https://railsafe-backend-xxxxxxxxxx.a.run.app`
4. Tap **"Test Connection"** to verify that a green confirmation banner appears:
   `Online! Model: RandomForestClassifier (100 Trees - MQ Multi-Sensor) (v1.0.0)`
5. Tap **"Save URL"**.

---

## 10. Updating the ML Model

If you retrain the Random Forest model:
1. Export the trained estimator from your notebook:
   ```python
   import pickle
   with open("railsafe_rf_model.pkl", "wb") as f:
       pickle.dump(model, f)
   ```
2. Copy the new `.pkl` file into `railsafe_backend/models/railsafe_rf_model.pkl`.
3. If new feature names or versions are introduced, update `MODEL_VERSION` in `config` or `.env`.
4. Run backend tests to verify mathematical equivalence:
   ```bash
   pytest tests/ -v
   ```
5. Rebuild and redeploy the container:
   ```bash
   docker build -t railsafe-backend:latest .
   ```

---

## 11. Common Errors and Troubleshooting

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **Port already allocated** (`Bind for 0.0.0.0:8000 failed`) | Another service on your computer is using port 8000. | Run container with `-e PORT=8080 -p 8080:8080`. |
| **HTTP 401 Unauthorized** | Missing or expired Bearer token. | Pass `Authorization: Bearer <VALID_FIREBASE_ID_TOKEN>` or use `DEMO_OFFICER_TOKEN` when `ALLOW_DEV_AUTH_BYPASS=true`. |
| **HTTP 422 Unprocessable Entity** | Sensor payload out of bounds or missing channel. | Ensure all 3 features (`mq2_raw`, `mq4_raw`, `mq7_raw`) are included within physical limits ($0 \le x \le 100,000$). |
| **Model file not found** | Incorrect `MODEL_PATH` environment variable. | Ensure `MODEL_PATH=models/railsafe_rf_model.pkl` is passed or left as default. |
| **Cleartext HTTP blocked on Android** | Android 9+ requires cleartext permission for non-HTTPS local IPs. | `android:usesCleartextTraffic="true"` is already enabled in `AndroidManifest.xml` for local development. For production, always use Cloud Run's `https://` address. |
