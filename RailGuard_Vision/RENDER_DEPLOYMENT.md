# RailGuard Vision — Render Free Cloud Deployment with Firebase Realtime Database

> [!IMPORTANT]
> **FOR HUMAN REVIEW ONLY** — RailGuard Vision is an optical surveillance early-warning prototype engineered for Indian Railways station premises. Visible-light optical cameras **CANNOT detect explosives, narcotics, or chemical hazards**. Alerts prioritize locations for human security personnel (RPF/GRP) to deploy certified physical inspection tools (X-ray, Explosive Trace Detection / ETD, and canine squads). The system does not implement facial recognition, biometric profiling, or automated enforcement.

---

## 1. Cloud Persistence Architecture: Firebase Realtime Database

### Architecture Overview
1. **Decoupled Cloud from SQLite:** The cloud API on Render no longer touches `/var/data` or requires local SQLite disk storage.
2. **Firebase Realtime Database (RTDB):** Persistent cloud alert records, timestamps, alert lifecycle, and operator review states are stored under `railguard/alerts/` with index at `railguard/event_uid_index/`.
3. **100% Render Free Tier Compatible:** Runs on Render Free Tier with no persistent disk attached.
4. **Firebase Storage for Binary Media:** JPEG snapshots and MP4 video clips are stored in Firebase Storage; RTDB only stores paths and URLs.
5. **Local Edge Preserved:** The station laptop continues using its local SQLite database (`data/security_alerts.db`) for real-time video buffering and offline resilience.

---

## 2. Distributed Architecture

```
┌──────────────────────────────────────┐
│       STATION LAPTOP (EDGE)          │
│ • Laptop USB Webcam / RTSP CCTV      │
│ • YOLOv8n + ByteTrack Multi-Tracking │
│ • Spatial-Temporal Rules Engine      │
│ • Local SQLite (security_alerts.db)  │
│ • Local Evidence (data/alerts/)      │
│ • Asynchronous Agent (src/agent.py)  │
└──────────────────┬───────────────────┘
                   │ Outbound Authenticated HTTPS (POST /api/ingest/alerts)
                   │ Header: Authorization: Bearer <RAILGUARD_AGENT_TOKEN>
                   ▼
┌──────────────────────────────────────┐
│     RENDER CLOUD BACKEND (FREE)      │
│ • FastAPI Web Service (app/api.py)   │
│ • Dynamic Port ($PORT)               │
│ • Free Tier Plan (No Disks Needed)   │
│ • Ingestion Auth: Agent Secret Token │
│ • Operator Auth: Firebase ID Token   │
│ • WebSockets (WSS /api/ws/alerts)    │
└──────────┬─────────────────┬─────────┘
           │                 │
           ▼                 ▼
┌───────────────────────┐ ┌──────────────────┐
│ FIREBASE REALTIME DB  │ │  FIREBASE AUTH   │
│ Node:                 │ │ Cryptographic    │
│ railguard/alerts/     │ │ Token Validation │
└───────────────────────┘ └──────────────────┘
           ▲
           │ Authenticated HTTPS (Bearer <Firebase_ID_Token>)
┌──────────┴───────────────────────────┐
│         FLUTTER MOBILE APP           │
│ • Signs in via Firebase Auth         │
│ • RailGuardApiService calls Render   │
│ • RPF Field Officer Alerts Screen    │
│ • Submits Verified / False Alarm     │
└──────────────────────────────────────┘
```

---

## 3. Render Dashboard Setup (Step-by-Step)

Follow these steps in the Render Dashboard to deploy on the **Free Tier**:

### Step 3.1: Create Web Service
1. Log in to [render.com](https://render.com) and click **New +** > **Web Service**.
2. Select your connected repository: `RailSafe-AI`.
3. Configure the service settings:
   - **Name:** `railguard-vision-api`
   - **Region:** `Oregon (US West)` or `Singapore`
   - **Branch:** `main`
   - **Root Directory:** `RailGuard_Vision` *(Important: points to the subproject folder)*
   - **Runtime:** `Python 3`
   - **Build Command:** `pip install --upgrade pip && pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.api:app --host 0.0.0.0 --port $PORT`
   - **Plan:** `Free` *(No paid persistent disk needed)*

### Step 3.2: Set Health Check Path
- Under **Advanced Settings**, set **Health Check Path** to `/health`.
*(Note: `/health` runs without external dependencies so Render's health prober succeeds immediately).*

### Step 3.3: Configure Environment Variables
Under the **Environment** tab in Render, enter the following key-value pairs:

| KEY | VALUE | Description |
| :--- | :--- | :--- |
| `PYTHON_VERSION` | `3.10.13` | Recommended stable Python version |
| `FIREBASE_PROJECT_ID` | `railsafe-ai-92d9f` | Your Firebase Project ID |
| `FIREBASE_DATABASE_URL` | `https://railsafe-ai-92d9f-default-rtdb.asia-southeast1.firebasedatabase.app/` | Firebase Realtime Database URL |
| `RTDB_ALERTS_PATH` | `railguard/alerts` | RTDB path for luggage alerts |
| `FIREBASE_STORAGE_BUCKET` | `railsafe-ai-92d9f.firebasestorage.app` | Default Firebase Storage bucket |
| `ALLOW_DEV_AUTH_BYPASS` | `false` | Disables testing bypass in production |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:54313` | Comma-separated frontend origins permitted for CORS |
| `RAILGUARD_AGENT_TOKEN` | *(Click **Generate** or enter random string)* | Secret token for station laptop agent |
| `FIREBASE_SERVICE_ACCOUNT_JSON`| *(Paste JSON contents - see Step 3.4)* | Service account credentials secret |

> [!IMPORTANT]
> Do NOT set `RAILGUARD_DATA_DIR=/var/data` on the Render Free Tier.

### Step 3.4: How to Obtain `FIREBASE_SERVICE_ACCOUNT_JSON`
1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Select your project: **railsafe-ai-92d9f**.
3. Click the **Gear icon (Project settings)** > **Service accounts** tab.
4. Click **Generate new private key** and confirm by clicking **Generate key**.
5. Open the downloaded `.json` file in a text editor (e.g., Notepad).
6. Copy the **entire JSON text** and paste it as the value of `FIREBASE_SERVICE_ACCOUNT_JSON` in Render.

Click **Create Web Service**.

---

## 4. Verification & Health Checks

Once Render displays **Live**, verify backend operation using Windows PowerShell, curl, or your browser:

### 4.1 Process Liveness Check (Public)
```powershell
curl -i https://railsafe-ai-backend.onrender.com/health
```
**Expected Response:** `HTTP 200 OK`
```json
{
  "status": "healthy",
  "service": "RailGuard Vision Cloud Backend",
  "version": "1.0.0",
  "persistence": "Firebase Realtime Database",
  "disclaimer": "FOR HUMAN REVIEW ONLY — Does not detect explosives, chemical substances, or narcotics."
}
```

### 4.2 Database Readiness Check (Public)
```powershell
curl -i https://railsafe-ai-backend.onrender.com/ready
```
**Expected Response:** `HTTP 200 OK`
```json
{
  "status": "ready",
  "rtdb_connected": true,
  "project_id": "railsafe-ai-92d9f",
  "database_url": "https://railsafe-ai-92d9f-default-rtdb.asia-southeast1.firebasedatabase.app/",
  "alerts_path": "railguard/alerts"
}
```

### 4.3 Protected Operator Endpoints (Requires Firebase Auth)
If you visit `https://railsafe-ai-backend.onrender.com/api/alerts` in a browser, it will return:
```json
{
  "detail": "Missing authentication token. Please provide a Bearer Firebase ID token."
}
```
> [!NOTE]
> This is **expected security behavior**, not a server bug. The browser does not send a Bearer token. Operator endpoints are designed to be accessed securely by authenticated Flutter screening officers.

---

## 5. Starting the Station Laptop Detection Agent

On the laptop connected to the webcam on the railway platform:

### 5.1 Step 1: Run Synthetic Ingestion Test (Recommended)
Before running the live webcam, verify your `RAILGUARD_AGENT_TOKEN` and Render Firestore connection in one command:
```powershell
cd "c:\Users\shanm\Downloads\RailSafe AI\RailGuard_Vision"

python run_agent.py --test-ingest --cloud-url "https://railsafe-ai-backend.onrender.com" --token "<PASTE_YOUR_RENDER_AGENT_TOKEN>"
```
This safely sends a single synthetic test alert and verifies that Render accepts it with `HTTP 201 Created` and records it in Cloud Firestore.

### 5.2 Step 2: Start Real-Time Webcam Detection Agent
```powershell
cd "c:\Users\shanm\Downloads\RailSafe AI\RailGuard_Vision"

# Set environment variables for the session
$env:RAILGUARD_CLOUD_URL = "https://railsafe-ai-backend.onrender.com"
$env:RAILGUARD_AGENT_TOKEN = "<PASTE_YOUR_RENDER_AGENT_TOKEN>"

# Run the agent with live desktop visual display
python run_agent.py --source 0 --display
```
Or directly with CLI arguments:
```powershell
python run_agent.py --source 0 --display --cloud-url "https://railsafe-ai-backend.onrender.com" --token "<PASTE_YOUR_RENDER_AGENT_TOKEN>"
```

### 5.3 Offline / Local-Only Mode (No Cloud Forwarding)
To run the webcam and rules engine purely locally on the laptop without sending anything to the cloud:
```powershell
python run_agent.py --source 0 --display --offline
```

### Edge-to-Cloud Behavior:
1. Laptop captures local frames from webcam `0`.
2. Runs YOLOv8n object detection and ByteTrack tracking locally.
3. Evaluates luggage stationarity and nearest-person heuristics.
4. When an unattended bag triggers `ALERT`, it logs to local SQLite and queues an upload task.
5. The background forwarder streams the alert and snapshot JPEG to Render via `POST /api/ingest/alerts`.
6. Render creates a document in Cloud Firestore (`railguard_alerts`) and persists evidence to Firebase Storage.
7. If internet disconnects, the edge camera continues operating uninterrupted. Up to 100 alerts queue locally and retry with exponential backoff once reconnected.

---

## 6. Flutter Mobile App Configuration

The Flutter app interfaces with the cloud backend through [`lib/services/railguard_api_service.dart`](file:///c:/Users/shanm/Downloads/RailSafe%20AI/lib/services/railguard_api_service.dart).

1. In the Flutter app settings (or [`LocalStorageService`](file:///c:/Users/shanm/Downloads/RailSafe%20AI/lib/services/local_storage_service.dart)), configure:
   - **Backend Base URL:** `https://railguard-vision-api.onrender.com`
2. When the user signs in with email/password via Firebase Authentication, `RailGuardApiService` automatically retrieves the user's real Firebase ID token via `AuthService.getIdToken()` and attaches:
   ```text
   Authorization: Bearer <Firebase_ID_Token>
   ```
3. Operators can:
   - View recent unattended luggage alerts in real-time.
   - Review an alert as **Verified** or **False Alarm**.
   - The reviewing officer's Firebase UID is recorded on the Firestore document.

---

## 7. Firebase Realtime Database Security Rules

Ensure your `database.rules.json` has restrictive rules that block direct client reads and writes while defining required query indexes:

```json
{
  "rules": {
    "railguard": {
      "alerts": {
        ".read": false,
        ".write": false,
        ".indexOn": [
          "created_at_ms",
          "review_status",
          "camera_id",
          "track_id",
          "event_uid"
        ]
      },
      "event_uid_index": {
        ".read": false,
        ".write": false
      }
    },
    "$other": {
      ".read": false,
      ".write": false
    }
  }
}
```

### Deploying Realtime Database Rules via Firebase CLI
Deploy the rules file without modifying Firestore rules:
```bash
firebase deploy --only database
```

---

## 8. Firestore to Realtime Database Data Migration Utility

If you have existing alert records in Cloud Firestore, run the provided standalone migration utility:

```powershell
cd "c:\Users\shanm\Downloads\RailSafe AI\RailGuard_Vision"

# 1. Dry run (Inspect planned changes safely without writing to RTDB)
python src/migrate_firestore_to_rtdb.py

# 2. Live migration (Copies records into RTDB, skips existing records, preserves Firestore)
python src/migrate_firestore_to_rtdb.py --live

# 3. Force overwrite if re-migrating
python src/migrate_firestore_to_rtdb.py --live --overwrite
```

---

## 9. API Reference Summary

| Method | Endpoint | Auth Header | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/health` | None | Public process liveness check for Render |
| `GET` | `/ready` | None | Public Realtime Database connectivity check |
| `POST`| `/api/ingest/alerts` | Bearer Agent Token | Ingests alert & snapshot into RTDB (Idempotent) |
| `POST`| `/api/ingest/alerts/clear` | Bearer Agent Token | Records cleared timestamp when bag is retrieved |
| `GET` | `/api/alerts` | Bearer Firebase ID Token | Lists alerts with limit and review_status filters |
| `GET` | `/api/alerts/{id}` | Bearer Firebase ID Token | Fetches alert details from RTDB |
| `PATCH`| `/api/alerts/{id}/review` | Bearer Firebase ID Token | Records Verified / False Alarm with reviewer UID |
| `GET` | `/api/alerts/{id}/snapshot`| Bearer Firebase ID Token | Streams JPEG evidence (path traversal guarded) |
| `GET` | `/api/alerts/{id}/clip`| Bearer Firebase ID Token | Streams MP4 video clip |
| `GET` | `/api/alerts/stats/false-alarm-rate`| Bearer Firebase ID Token | False alarm rate metrics from reviewed alerts |
| `WSS` | `/api/ws/alerts` | Token Query Param | Real-time WebSocket push notifications |

---

## 10. Security & Privacy Safeguards

- [x] **No `/var/data` Dependency:** Deploys on Render Free without filesystem permission issues.
- [x] **Cryptographic Auth:** Mobile operator requests are validated using Firebase Admin SDK public keys.
- [x] **Separated Agent Ingestion:** Laptop edge camera uses a dedicated `RAILGUARD_AGENT_TOKEN`.
- [x] **Idempotent Ingestion:** Duplicate event transmissions reuse `event_uid` as document ID, preventing duplicate records.
- [x] **Traversal Prevention:** Evidence delivery enforces strict containment within container storage.
- [x] **No Facial Recognition / Biometrics:** Completely strictly adheres to early-warning optical screening without demographic profiling.
