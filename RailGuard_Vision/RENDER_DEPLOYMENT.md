# RailGuard Vision — Render Cloud Deployment & Operator Runbook

> [!IMPORTANT]
> **FOR HUMAN REVIEW ONLY** — RailGuard Vision is an optical surveillance early-warning prototype engineered for Indian Railways premises. Visible-light optical cameras **CANNOT detect explosives, narcotics, or chemical hazards**. Alerts prioritize locations for human security personnel (RPF) to deploy certified physical inspection tools (X-ray, Explosive Trace Detection / ETD, or canine squads). The system does not implement facial recognition, biometric profiling, or automated enforcement.

---

## 1. System Topology & Architecture

RailGuard Vision separates optical computer vision processing at the station edge from centralized cloud storage and mobile push notification delivery:

```
┌──────────────────────────────────────┐
│       STATION LAPTOP (EDGE)          │
│ • Laptop USB Webcam / RTSP CCTV      │
│ • YOLOv8n + ByteTrack Multi-Tracking │
│ • Spatial-Temporal Rules Engine      │
│ • Local Rolling Buffer (10s Context) │
│ • Non-Blocking Asynchronous Forwarder│
└──────────────────┬───────────────────┘
                   │ Outbound Authenticated HTTPS (POST /api/ingest/alerts)
                   ▼
┌──────────────────────────────────────┐
│       RENDER CLOUD BACKEND           │
│ • FastAPI Web Service (app/api.py)   │
│ • Dynamic Port ($PORT)               │
│ • Bearer Token Auth Guard            │
│ • Path-Traversal Hardened Endpoints  │
│ • WebSockets (WSS /api/ws/alerts)    │
│ • Persistent Disk Mount (/var/data)  │
│   ├─ security_alerts.db (SQLite)     │
│   ├─ alerts/ (JPEG Snapshots)        │
│   └─ clips/ (MP4 Video Context)      │
└──────────────────┬───────────────────┘
                   │ Authenticated HTTPS / WSS
                   ▼
┌──────────────────────────────────────┐
│         FLUTTER MOBILE APP           │
│ • RPF Field Officer Alerts Screen    │
│ • Live Push Notifications            │
│ • Verified / False Alarm Audit Trail │
│ • Running False Alarm Rate Counter   │
└──────────────────────────────────────┘
```

---

## 2. Prerequisites

1. **Render Account:** Sign up at [render.com](https://render.com).
2. **Instance Plan:** A Render **Starter** plan ($7/mo) or higher is required for persistent disk support (`/var/data`). Render Free instances do not support attached disks.
3. **Local Station Machine:** Laptop with Python 3.10+, USB webcam or RTSP feed, and internet connectivity.
4. **Git Repository:** Pushed to GitHub/GitLab containing the `RailGuard_Vision` folder or root repository.

---

## 3. Render Dashboard Setup (Step-by-Step)

Follow these manual steps in the Render Dashboard to deploy the backend:

### Step 3.1: Create a New Web Service
1. Log in to your Render Dashboard and click **New +** > **Web Service**.
2. Connect your Git repository (`RailSafe-AI`).
3. Set the following basic parameters:
   - **Name:** `railguard-vision-api`
   - **Region:** `Oregon (US West)` or `Singapore (Southeast Asia)`
   - **Branch:** `main`
   - **Root Directory:** `RailGuard_Vision` (Important! Points to the subproject folder)
   - **Runtime:** `Python 3`
   - **Build Command:** `pip install --upgrade pip && pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.api:app --host 0.0.0.0 --port $PORT`
   - **Instance Type:** `Starter` ($7/month) — *Required for persistent disk*

### Step 3.2: Attach Persistent Disk Storage
1. Scroll down to the **Disks** section in the service creation settings (or go to **Disks** tab).
2. Click **Add Disk**:
   - **Disk Name:** `railguard-data`
   - **Mount Path:** `/var/data`
   - **Size:** `1 GB` (or larger depending on evidence retention policies)

### Step 3.3: Configure Health Check Path
1. Under **Advanced Settings**, locate **Health Check Path**.
2. Enter: `/health`

### Step 3.4: Configure Environment Variables
In the **Environment Variables** tab, add the following variables:

| Variable Name | Example / Recommended Value | Description |
| :--- | :--- | :--- |
| `PYTHON_VERSION` | `3.10.13` | Recommended stable Python runtime on Render |
| `RAILGUARD_DATA_DIR` | `/var/data` | Persistent disk root mount path |
| `RAILGUARD_DB_PATH` | `/var/data/security_alerts.db` | Persistent SQLite database file |
| `RAILGUARD_ALERTS_DIR`| `/var/data/alerts` | Snapshot evidence storage path |
| `RAILGUARD_CLIPS_DIR` | `/var/data/clips` | Context video clip storage path |
| `RAILGUARD_API_TOKEN` | *(Generate a random 32-char string)* | Secret token for Flutter app & operators |
| `RAILGUARD_AGENT_TOKEN`| *(Generate a random 32-char string)* | Secret token for station laptop agent |

> [!CAUTION]
> Never share or commit `RAILGUARD_API_TOKEN` or `RAILGUARD_AGENT_TOKEN` to source control. Use Render's Secret File or Environment Variable encryption.

Click **Create Web Service**. Render will build and deploy the container.

---

## 4. Verification & Health Checks

Once the deployment finishes and shows **Live**, verify backend operation using Windows PowerShell or curl:

### Health Check (Unauthenticated)
```powershell
curl -i https://railguard-vision-api.onrender.com/health
```
**Expected Response:**
```json
HTTP/1.1 200 OK
Content-Type: application/json

{
  "status": "healthy",
  "service": "RailGuard Vision Cloud Backend",
  "version": "1.0.0",
  "storage_ready": true,
  "disclaimer": "FOR HUMAN REVIEW ONLY — Does not detect explosives, chemical substances, or narcotics."
}
```

### Authenticated Alerts Query
```powershell
curl -i -H "Authorization: Bearer <YOUR_RAILGUARD_API_TOKEN>" https://railguard-vision-api.onrender.com/api/alerts
```
**Expected Response:** `HTTP/1.1 200 OK` with JSON array `[]`.

---

## 5. Starting the Local Station Detection Agent

On the laptop running the USB webcam at the railway station:

### Windows PowerShell Launch Command:
```powershell
cd "c:\Users\shanm\Downloads\RailSafe AI\RailGuard_Vision"

# Set target cloud backend and agent token
$env:RAILGUARD_CLOUD_URL = "https://railguard-vision-api.onrender.com"
$env:RAILGUARD_AGENT_TOKEN = "<YOUR_RAILGUARD_AGENT_TOKEN>"

# Run the agent with live desktop visual display
python run_agent.py --display
```

### Alternatively via batch script:
```cmd
cd "c:\Users\shanm\Downloads\RailSafe AI\RailGuard_Vision"
set RAILGUARD_CLOUD_URL=https://railguard-vision-api.onrender.com
set RAILGUARD_AGENT_TOKEN=<YOUR_RAILGUARD_AGENT_TOKEN>
run_agent.bat
```

### What Happens:
1. Opens laptop webcam (`0`).
2. Runs YOLOv8n object detection and ByteTrack tracking locally at maximum hardware speed.
3. Evaluates luggage stationarity and nearest-person owner heuristics.
4. When a bag is stationary for > 15s without an owner, local pipeline raises an `ALERT`.
5. Synthesizes a JPEG snapshot and an ~10s rolling context MP4 clip.
6. The background uploader non-blockingly streams the event and evidence to Render over HTTPS.
7. If internet is temporarily lost, events queue locally (up to 100 items) and retry with exponential backoff once reconnected.

---

## 6. Configuring the Flutter Mobile App

The Flutter mobile application interfaces with the cloud backend through [`lib/services/railguard_api_service.dart`](file:///c:/Users/shanm/Downloads/RailSafe%20AI/lib/services/railguard_api_service.dart).

### Setting Cloud URL in App:
In the app's settings screen (or [`LocalStorageService`](file:///c:/Users/shanm/Downloads/RailSafe%20AI/lib/services/local_storage_service.dart)):
- Set Backend URL to: `https://railguard-vision-api.onrender.com`
- Set Bearer Token to: `<YOUR_RAILGUARD_API_TOKEN>`

### Available Mobile Operations:
- **`getAlerts()`:** Fetches active and recent unattended luggage alerts.
- **`reviewAlert(id, 'verified')`:** Field officer verifies alert on premises.
- **`reviewAlert(id, 'false_alarm')`:** Field officer marks false alarm (e.g., owner was just sitting nearby outside camera angle).
- **`getSnapshotUrl(id)`:** Loads snapshot evidence in app.
- **`getClipUrl(id)`:** Plays context video evidence.
- **`getFalseAlarmRate()`:** Computes running false-alarm rate across reviewed events.

---

## 7. API Reference Summary

| Method | Endpoint | Auth Required | Purpose |
| :--- | :--- | :---: | :--- |
| `GET` | `/health` | No | System health and storage status |
| `POST`| `/api/ingest/alerts` | Agent Token | Multipart upload of alert + snapshot + clip |
| `POST`| `/api/ingest/alerts/clear` | Agent Token | Notification that active alert has cleared |
| `GET` | `/api/alerts` | API Token | List alerts (supports `?limit=50&unreviewed_only=true`) |
| `GET` | `/api/alerts/{id}` | API Token | Retrieve single alert details |
| `PATCH`| `/api/alerts/{id}/review` | API Token | Operator review: `{"review_status": "verified"\|"false_alarm"}` |
| `GET` | `/api/alerts/{id}/snapshot` | API Token | Stream high-res JPEG snapshot (safe traversal guard) |
| `GET` | `/api/alerts/{id}/clip` | API Token | Stream MP4 context video clip |
| `GET` | `/api/alerts/stats/false-alarm-rate`| API Token | False alarm rate statistics |
| `WSS` | `/api/ws/alerts` | API Token | WebSocket live event push feed |

---

## 8. Backup, Retention & Recovery Procedures

### Disk Capacity & Evidence Retention
- Snapshots: ~150 KB each.
- 10-second MP4 clips: ~2.5 MB each.
- A 1 GB persistent disk holds approximately **350 complete alert events** (snapshots + video clips).
- To prevent disk exhaustion, configure periodic log pruning or extend disk size in Render dashboard (`Disks` > `Resize`).

### Manual SQLite Backup Command (PowerShell):
```powershell
# If using Render SSH / Shell:
sqlite3 /var/data/security_alerts.db ".backup '/var/data/backup_$(date +%Y%m%d).db'"
```

### Rollback Process
In the Render Dashboard:
1. Navigate to **railguard-vision-api** > **Deploys**.
2. Select the previous stable deploy commit.
3. Click **Rollback to this deploy**.
4. The persistent disk at `/var/data` remains untouched and reattaches immediately to the previous container version.

---

## 9. Security & Privacy Checklist

- [x] **No Hardcoded Tokens:** Tokens are injected via environment variables only.
- [x] **Path Traversal Protection:** All file streaming endpoints validate that resolved paths reside strictly inside allowed evidence subdirectories.
- [x] **Idempotent Ingestion:** Retries with identical `event_uid` never create duplicate database rows.
- [x] **Strict Safety Disclaimer:** Every alert payload displays `FOR HUMAN REVIEW ONLY`.
- [x] **No Biometrics:** No facial recognition, age, gender, or demographic inferences are made.
- [x] **Outbound-Only Edge Connection:** The laptop never opens listening ports or requires inbound internet tunnels.
