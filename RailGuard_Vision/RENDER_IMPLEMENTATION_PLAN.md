# RailGuard Vision — Render Cloud Deployment & Ingestion Architecture Plan

## 1. Executive Summary & Objective

The objective of this deployment is to bridge **RailGuard Vision**'s optical edge detection on a local laptop (processing real-time Indian Railways surveillance video from USB webcams, RTSP streams, or local video files) to a cloud-hosted **FastAPI** backend on **Render**, backed by persistent storage mounted at `/var/data`. The cloud service exposes authenticated HTTPS endpoints for event ingestion, evidence storage, alert lifecycle audits, and real-time mobile push notifications to the **RailSafe AI** Flutter application.

---

## 2. Target Architecture & Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           LOCAL LAPTOP (STATION PREMISES)                       │
│                                                                                 │
│   ┌─────────────────────┐                                                       │
│   │  Webcam / RTSP (0)  │                                                       │
│   └──────────┬──────────┘                                                       │
│              ▼                                                                  │
│   ┌─────────────────────┐        ┌──────────────────────┐                       │
│   │ RailGuard Pipeline  │───────►│  Streamlit Local HUD │ (Local Operator View) │
│   │ (YOLOv8 + ByteTrack)│        └──────────────────────┘                       │
│   └──────────┬──────────┘                                                       │
│              │ Active / Cleared Events + Evidence                               │
│              ▼                                                                  │
│   ┌─────────────────────────────────────────────────────────┐                   │
│   │              Local Cloud Forwarding Agent               │                   │
│   │  • Bounded Local Task Queue (Max 100 items)             │                   │
│   │  • Idempotent Event Uploader with Exponential Backoff   │                   │
│   │  • Non-blocking Worker Thread                           │                   │
│   └────────────────────────────┬────────────────────────────┘                   │
└────────────────────────────────┼────────────────────────────────────────────────┘
                                 │ Outbound Authenticated HTTPS
                                 │ (POST /api/ingest/alerts)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           RENDER CLOUD BACKEND (HTTPS)                          │
│                                                                                 │
│   ┌────────────────────────────────────────────────────────┐                    │
│   │              FastAPI Cloud Backend (app/api.py)        │                    │
│   │  • Port: $PORT (0.0.0.0)                               │                    │
│   │  • Token Auth (Bearer Token / Header Auth)             │                    │
│   │  • Rate Limiting & File Size Enforcers                 │                    │
│   │  • WebSocket Broadcaster (WSS /api/ws/alerts)          │                    │
│   └───────────────┬────────────────────────┬───────────────┘                    │
│                   │                        │                                    │
│                   ▼                        ▼                                    │
│   ┌───────────────────────────────┐ ┌──────────────────────────────────────┐    │
│   │ Persistent Disk (/var/data)   │ │  Restricted Evidence Delivery        │    │
│   │ • SQLite: /var/data/alerts.db │ │  • Traversal-safe file streaming     │    │
│   │ • Snaps: /var/data/alerts/    │ │  • GET /api/alerts/{id}/snapshot     │    │
│   │ • Clips: /var/data/clips/     │ │  • GET /api/alerts/{id}/clip         │    │
│   └───────────────────────────────┘ └──────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┬──────────────────────┘
                                                           │ Authenticated HTTPS / WSS
                                                           ▼
                                            ┌─────────────────────────────┐
                                            │      Flutter Mobile App     │
                                            │  (RPF Field Officer Client) │
                                            └─────────────────────────────┘
```

---

## 3. Storage & Configuration Strategy

### 3.1 Environment Variables
| Variable | Default (Local) | Render Value | Purpose |
| :--- | :--- | :--- | :--- |
| `PORT` | `8000` | Render-assigned (e.g. `10000`) | FastAPI binding port |
| `RAILGUARD_DATA_DIR` | `data` | `/var/data` | Persistent disk root mount |
| `RAILGUARD_DB_PATH` | `data/security_alerts.db` | `/var/data/security_alerts.db` | SQLite database file location |
| `RAILGUARD_ALERTS_DIR` | `data/alerts` | `/var/data/alerts` | Snapshot evidence directory |
| `RAILGUARD_CLIPS_DIR` | `data/clips` | `/var/data/clips` | Context video clip directory |
| `RAILGUARD_API_TOKEN` | *dev-token* | Secret Token | Mobile & Operator API authentication |
| `RAILGUARD_AGENT_TOKEN`| *agent-token* | Secret Token | Laptop camera ingestion agent authentication |
| `RAILGUARD_CONFIG` | `configs/config.yaml` | `configs/config.yaml` | System configuration override path |

### 3.2 Non-Destructive Database Schema Extension
To support idempotency and retry deduplication, the SQLite schema will be upgraded non-destructively:
```sql
ALTER TABLE alerts ADD COLUMN event_uid TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_alerts_event_uid ON alerts(event_uid);
```
- Existing databases remain 100% compatible.
- Ingestion retries matching an existing `event_uid` return the existing record with HTTP 200 without creating duplicate rows.

---

## 4. Ingestion Protocol & Security Specifications

### 4.1 Ingestion Endpoint: `POST /api/ingest/alerts`
- **Authentication:** `Authorization: Bearer <RAILGUARD_AGENT_TOKEN>`
- **Content-Type:** `multipart/form-data`
- **Fields:**
  - `event_uid` (UUID string / unique key, required)
  - `timestamp` (ISO8601 string, required)
  - `camera_id` (string, required)
  - `track_id` (integer, required)
  - `object_class` (string: backpack, handbag, suitcase, required)
  - `event_duration` (float, required)
  - `reason` (string, required)
  - `snapshot` (UploadFile: image/jpeg, max 5 MB, required)
  - `clip` (UploadFile: video/mp4, max 25 MB, optional)
- **Validation & Hardening:**
  - Max total request payload: 30 MB.
  - Server-side filename generation: `snapshot_{safe_camera}_{track_id}_{uuid[:8]}.jpg`.
  - Content sanitization to prevent path traversal (`os.path.basename` and strict subpath resolution).
  - Broadcasts new event over active WebSockets to connected mobile clients.

### 4.2 Clear Endpoint: `POST /api/ingest/alerts/clear`
- Marks active alert cleared when passenger returns or luggage is removed.
- Updates `cleared_timestamp` in SQLite.

---

## 5. Laptop Detection Agent (`src/agent.py` & `run_agent.py`)

- Runs local `RailGuardPipeline` with laptop webcam (`0`).
- Runs an asynchronous, thread-safe background worker with a bounded `queue.Queue(maxsize=100)`.
- Never blocks camera capture or ByteTrack inference.
- Handles network disconnections gracefully with exponential backoff (`2^attempt` sec, capped at 30 sec).
- Preserves local snapshots and clips locally while queuing cloud sync.

---

## 6. Flutter Mobile Integration

- Implement `RailGuardApiService` in Flutter (`lib/services/railguard_api_service.dart`).
- Supports:
  - `GET /health` (backend liveness check)
  - `GET /api/alerts` (retrieve unreviewed or recent security alerts)
  - `PATCH /api/alerts/{id}/review` (mark Verified or False Alarm)
  - `GET /api/alerts/{id}/snapshot` (view high-resolution JPEG evidence)
  - `GET /api/alerts/{id}/clip` (stream MP4 video clip context)
  - `WSS /api/ws/alerts` (live push events to RPF personnel)
- Prototype token authentication with documented migration path to Firebase Auth JWT tokens.

---

## 7. Render Configuration & Artifacts

- `render.yaml`: Infrastructure as Code (Blueprint) with Web Service + Persistent Disk (`/var/data`, 1 GB).
- `requirements.txt`: Update with `fastapi`, `uvicorn[standard]`, `pydantic`, `python-multipart`, `aiofiles`, `httpx`.
- `RENDER_DEPLOYMENT.md`: Operator runbook with manual Render Dashboard steps, environment configuration, Windows agent launch commands, and disaster recovery procedures.

---

## 8. Safety, Ethical & Privacy Commitments

1. **Human Review Only:** Every API alert payload includes `disclaimer: "FOR HUMAN REVIEW ONLY — Does not detect explosives or narcotics. Verify physical context."`.
2. **No Facial Recognition:** No biometric features are captured, processed, or persisted.
3. **Restricted Evidence Access:** Evidence files are served strictly via authenticated endpoints with strict directory traversal prevention.
