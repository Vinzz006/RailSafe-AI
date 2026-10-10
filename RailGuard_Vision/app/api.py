"""FastAPI Cloud Backend for RailGuard Vision.

Provides secure endpoints for:
- Health check and system liveness
- Authenticated camera agent ingestion (POST /api/ingest/alerts)
- Mobile operator alert retrieval and review (Flutter client)
- Path-traversal safe evidence delivery (snapshots & clips)
- Real-time WebSocket event broadcasting
"""

from __future__ import annotations

import contextlib
import logging
import os
import re
from pathlib import Path
from typing import Any, AsyncGenerator, Dict, List, Optional, Set

from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Query,
    Security,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

from src.config import SystemConfig, load_config
from src.db import AlertDatabaseManager, AlertRecord

# Configure sanitized logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] [RAILGUARD_API] %(message)s",
)
logger = logging.getLogger("railguard_api")

# Load configuration and initialize database
config: SystemConfig = load_config()
db: AlertDatabaseManager = AlertDatabaseManager(config.storage.db_path)

# Ensure persistent evidence storage directories exist
Path(config.storage.alerts_dir).mkdir(parents=True, exist_ok=True)
Path(config.storage.clips_dir).mkdir(parents=True, exist_ok=True)
Path(config.storage.db_path).parent.mkdir(parents=True, exist_ok=True)

# Security bearer scheme (auto_error=False to allow query token fallback)
security_scheme = HTTPBearer(auto_error=False)


# ============================================================================
# WebSocket Connection Manager
# ============================================================================
class WebSocketManager:
    """Manages active WebSocket connections for push alert broadcasting."""

    def __init__(self) -> None:
        self.active_connections: Set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections.add(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        self.active_connections.discard(websocket)

    async def broadcast(self, message: Dict[str, Any]) -> None:
        dead_connections = set()
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                dead_connections.add(connection)
        for dead in dead_connections:
            self.active_connections.discard(dead)


ws_manager = WebSocketManager()


# ============================================================================
# Application Lifespan
# ============================================================================
@contextlib.asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    logger.info("RailGuard Vision Cloud API initialized.")
    logger.info("Database: %s", config.storage.db_path)
    logger.info("Alerts Dir: %s", config.storage.alerts_dir)
    logger.info("Clips Dir: %s", config.storage.clips_dir)
    yield
    logger.info("RailGuard Vision Cloud API shutting down.")


app = FastAPI(
    title="RailGuard Vision API",
    version=config.app.version,
    description="Early-warning unattended luggage screening assistance API for Indian Railways.",
    lifespan=lifespan,
)

# Enable CORS for Flutter mobile integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Authentication Dependencies
# ============================================================================
def verify_api_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Security(security_scheme),
    token_query: Optional[str] = Query(None, alias="token"),
) -> str:
    """Verify bearer token or query token for mobile operator endpoints."""
    provided_token = None
    if credentials:
        provided_token = credentials.credentials
    elif token_query:
        provided_token = token_query

    expected_api = config.security.api_token
    expected_agent = config.security.agent_token

    if not provided_token or provided_token not in (expected_api, expected_agent):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized: Invalid or missing authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return provided_token


def verify_agent_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Security(security_scheme),
    token_query: Optional[str] = Query(None, alias="token"),
) -> str:
    """Verify authentication for camera ingestion agent."""
    provided_token = None
    if credentials:
        provided_token = credentials.credentials
    elif token_query:
        provided_token = token_query

    expected_agent = config.security.agent_token
    expected_api = config.security.api_token

    if not provided_token or provided_token not in (expected_agent, expected_api):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized: Invalid camera ingestion agent token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return provided_token


# ============================================================================
# Pydantic Schemas
# ============================================================================
class ReviewUpdateRequest(BaseModel):
    review_status: str = Field(..., description="'verified' or 'false_alarm'")


class ClearAlertRequest(BaseModel):
    camera_id: str
    track_id: int
    cleared_timestamp: str
    event_uid: Optional[str] = None


class AlertResponse(BaseModel):
    id: int
    event_uid: Optional[str] = None
    timestamp: str
    camera_id: str
    track_id: int
    object_class: str
    event_duration: float
    reason: str
    snapshot_url: str
    clip_url: Optional[str] = None
    review_status: str
    cleared_timestamp: Optional[str] = None
    created_at: Optional[str] = None
    disclaimer: str = (
        "FOR HUMAN REVIEW ONLY — Does not detect explosives or narcotics. Verify physical context."
    )


def serialize_alert(alert: AlertRecord) -> AlertResponse:
    """Convert AlertRecord to API response model with authenticated resource URLs."""
    snap_url = f"/api/alerts/{alert.id}/snapshot"
    clip_url = f"/api/alerts/{alert.id}/clip" if alert.clip_path else None
    return AlertResponse(
        id=alert.id,
        event_uid=alert.event_uid,
        timestamp=alert.timestamp,
        camera_id=alert.camera_id,
        track_id=alert.track_id,
        object_class=alert.object_class,
        event_duration=alert.event_duration,
        reason=alert.reason,
        snapshot_url=snap_url,
        clip_url=clip_url,
        review_status=alert.review_status,
        cleared_timestamp=alert.cleared_timestamp,
        created_at=alert.created_at,
    )


# ============================================================================
# Path Traversal Guard
# ============================================================================
def validate_safe_evidence_path(filepath_str: str, allowed_dirs: List[str]) -> Path:
    """Ensure requested evidence path exists and resolves inside allowed directory."""
    raw_path = Path(filepath_str)
    if not raw_path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Requested evidence file not found on storage.",
        )

    resolved_file = raw_path.resolve()
    is_safe = False
    for ad in allowed_dirs:
        resolved_allowed = Path(ad).resolve()
        try:
            resolved_file.relative_to(resolved_allowed)
            is_safe = True
            break
        except ValueError:
            continue

    if not is_safe:
        logger.warning("Path traversal attempt blocked: %s", filepath_str)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden: Evidence path is outside permitted storage boundaries.",
        )

    return resolved_file


# ============================================================================
# Health & Status Endpoints
# ============================================================================
@app.get("/health", tags=["System"])
def health_check() -> Dict[str, Any]:
    """Public health and readiness check without exposing secrets or paths."""
    storage_ok = Path(config.storage.alerts_dir).is_dir() and Path(config.storage.clips_dir).is_dir()
    return {
        "status": "healthy" if storage_ok else "degraded",
        "service": "RailGuard Vision Cloud Backend",
        "version": config.app.version,
        "storage_ready": storage_ok,
        "disclaimer": config.app.disclaimer,
    }


# ============================================================================
# Ingestion Endpoints (Camera Agent -> Cloud)
# ============================================================================
@app.post(
    "/api/ingest/alerts",
    tags=["Ingestion"],
    status_code=status.HTTP_201_CREATED,
)
async def ingest_alert(
    event_uid: str = Form(...),
    timestamp: str = Form(...),
    camera_id: str = Form(...),
    track_id: int = Form(...),
    object_class: str = Form(...),
    event_duration: float = Form(...),
    reason: str = Form(...),
    snapshot: UploadFile = File(...),
    clip: Optional[UploadFile] = File(None),
    _token: str = Depends(verify_agent_token),
) -> Dict[str, Any]:
    """Ingest an unattended luggage alert raised by the local camera agent.
    
    Includes snapshot and optional rolling buffer clip. Idempotent on event_uid.
    """
    # 1. Validate fields
    if not event_uid or len(event_uid) < 4:
        raise HTTPException(status_code=400, detail="Invalid event_uid.")
    if track_id < 0 or event_duration < 0:
        raise HTTPException(status_code=400, detail="Invalid track_id or event_duration.")

    # 2. Check for duplicate ingestion via event_uid (Idempotency)
    existing = db.get_alert_by_uid(event_uid)
    if existing:
        logger.info("Alert %s already exists in database (id=%d). Skipping re-insert.", event_uid, existing.id)
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "status": "already_exists",
                "alert_id": existing.id,
                "event_uid": existing.event_uid,
                "message": "Event previously ingested. Duplicate suppressed.",
            },
        )

    # 3. Validate snapshot file
    if not snapshot.content_type or not snapshot.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Snapshot must be a valid image file.")

    # 4. Save snapshot with sanitized server-side filename
    safe_cam = re.sub(r"[^a-zA-Z0-9_\-]", "_", camera_id)
    safe_uid = re.sub(r"[^a-zA-Z0-9_\-]", "_", event_uid)[:12]
    snap_filename = f"snap_{safe_cam}_trk{track_id}_{safe_uid}.jpg"
    snap_dest = Path(config.storage.alerts_dir).resolve() / snap_filename

    snap_bytes = await snapshot.read()
    if len(snap_bytes) > 10 * 1024 * 1024:  # 10 MB limit for snapshot
        raise HTTPException(status_code=413, detail="Snapshot file exceeds 10MB limit.")

    with open(snap_dest, "wb") as f:
        f.write(snap_bytes)

    # 5. Save optional context clip
    clip_path_str: Optional[str] = None
    if clip is not None and clip.filename:
        clip_bytes = await clip.read()
        if len(clip_bytes) > 30 * 1024 * 1024:  # 30 MB limit for clip
            raise HTTPException(status_code=413, detail="Clip file exceeds 30MB limit.")

        ext = ".mp4" if "mp4" in (clip.content_type or "") or clip.filename.endswith(".mp4") else ".avi"
        clip_filename = f"clip_{safe_cam}_trk{track_id}_{safe_uid}{ext}"
        clip_dest = Path(config.storage.clips_dir).resolve() / clip_filename
        with open(clip_dest, "wb") as f:
            f.write(clip_bytes)
        clip_path_str = str(clip_dest)

    # 6. Insert into persistent SQLite
    alert_id = db.insert_alert(
        timestamp=timestamp,
        camera_id=camera_id,
        track_id=track_id,
        object_class=object_class,
        event_duration=event_duration,
        reason=reason,
        snapshot_path=str(snap_dest),
        clip_path=clip_path_str,
        review_status="unreviewed",
        cleared_timestamp=None,
        event_uid=event_uid,
    )

    created_alert = db.get_alert_by_id(alert_id)
    if created_alert:
        # Broadcast real-time event to connected mobile devices
        await ws_manager.broadcast({
            "event": "new_alert",
            "alert": serialize_alert(created_alert).model_dump(),
        })

    logger.info("Ingested new alert id=%d (uid=%s, cam=%s, trk=%d)", alert_id, event_uid, camera_id, track_id)
    return {
        "status": "created",
        "alert_id": alert_id,
        "event_uid": event_uid,
        "message": "Alert successfully recorded and evidence saved.",
    }


@app.post("/api/ingest/alerts/clear", tags=["Ingestion"])
async def ingest_alert_cleared(
    req: ClearAlertRequest,
    _token: str = Depends(verify_agent_token),
) -> Dict[str, Any]:
    """Update database when an active unattended alert clears on the camera agent."""
    rows = db.update_cleared_timestamp(
        track_id=req.track_id,
        camera_id=req.camera_id,
        cleared_timestamp=req.cleared_timestamp,
    )
    if rows > 0:
        await ws_manager.broadcast({
            "event": "alert_cleared",
            "camera_id": req.camera_id,
            "track_id": req.track_id,
            "cleared_timestamp": req.cleared_timestamp,
        })
    logger.info("Cleared alert for cam=%s trk=%d (rows=%d)", req.camera_id, req.track_id, rows)
    return {"status": "success", "rows_updated": rows}


# ============================================================================
# Mobile & Operator Alert Endpoints (Flutter Client)
# ============================================================================
@app.get("/api/alerts", tags=["Alerts"], response_model=List[AlertResponse])
def get_alerts(
    limit: int = Query(50, ge=1, le=500),
    unreviewed_only: bool = Query(False),
    status_filter: Optional[str] = Query(None, alias="status"),
    _token: str = Depends(verify_api_token),
) -> List[AlertResponse]:
    """List historical and active security alerts."""
    records = db.get_alerts(limit=limit, unreviewed_only=unreviewed_only)
    if status_filter:
        records = [r for r in records if r.review_status == status_filter]
    return [serialize_alert(r) for r in records]


@app.get("/api/alerts/{alert_id}", tags=["Alerts"], response_model=AlertResponse)
def get_alert_detail(
    alert_id: int,
    _token: str = Depends(verify_api_token),
) -> AlertResponse:
    """Retrieve details for a specific alert."""
    record = db.get_alert_by_id(alert_id)
    if not record:
        raise HTTPException(status_code=404, detail="Alert not found.")
    return serialize_alert(record)


@app.patch("/api/alerts/{alert_id}/review", tags=["Alerts"], response_model=AlertResponse)
@app.post("/api/alerts/{alert_id}/review", tags=["Alerts"], response_model=AlertResponse)
async def update_alert_review(
    alert_id: int,
    req: ReviewUpdateRequest,
    _token: str = Depends(verify_api_token),
) -> AlertResponse:
    """Update operator review status ('verified' or 'false_alarm')."""
    if req.review_status not in ("verified", "false_alarm"):
        raise HTTPException(
            status_code=400,
            detail="review_status must be either 'verified' or 'false_alarm'.",
        )

    record = db.get_alert_by_id(alert_id)
    if not record:
        raise HTTPException(status_code=404, detail="Alert not found.")

    success = db.update_review_status(alert_id, req.review_status)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to update review status.")

    updated = db.get_alert_by_id(alert_id)
    assert updated is not None

    # Broadcast review update to Flutter clients
    await ws_manager.broadcast({
        "event": "alert_reviewed",
        "alert_id": alert_id,
        "review_status": req.review_status,
    })

    logger.info("Alert %d reviewed as '%s'", alert_id, req.review_status)
    return serialize_alert(updated)


@app.get("/api/alerts/stats/false-alarm-rate", tags=["Alerts"])
def get_false_alarm_rate(
    _token: str = Depends(verify_api_token),
) -> Dict[str, Any]:
    """Retrieve running false alarm rate statistics."""
    rate, total, false_alarms = db.get_false_alarm_rate()
    return {
        "false_alarm_rate": rate,
        "total_reviewed": total,
        "false_alarms": false_alarms,
        "note": "Rate is computed strictly from operator reviews.",
    }


# ============================================================================
# Evidence Streaming Endpoints (Safe File Delivery)
# ============================================================================
@app.get("/api/alerts/{alert_id}/snapshot", tags=["Evidence"])
def get_alert_snapshot(
    alert_id: int,
    _token: str = Depends(verify_api_token),
) -> FileResponse:
    """Retrieve verified JPEG snapshot evidence for an alert."""
    record = db.get_alert_by_id(alert_id)
    if not record or not record.snapshot_path:
        raise HTTPException(status_code=404, detail="Snapshot not available for this alert.")

    allowed = [
        config.storage.alerts_dir,
        config.storage.data_dir or config.storage.alerts_dir,
        "data/alerts",
    ]
    safe_path = validate_safe_evidence_path(record.snapshot_path, allowed)
    return FileResponse(
        path=safe_path,
        media_type="image/jpeg",
        filename=safe_path.name,
    )


@app.get("/api/alerts/{alert_id}/clip", tags=["Evidence"])
def get_alert_clip(
    alert_id: int,
    _token: str = Depends(verify_api_token),
) -> FileResponse:
    """Retrieve approximately 10-second contextual video clip for an alert."""
    record = db.get_alert_by_id(alert_id)
    if not record or not record.clip_path:
        raise HTTPException(status_code=404, detail="Video clip not available for this alert.")

    allowed = [
        config.storage.clips_dir,
        config.storage.data_dir or config.storage.clips_dir,
        "data/clips",
    ]
    safe_path = validate_safe_evidence_path(record.clip_path, allowed)
    media_type = "video/mp4" if safe_path.suffix.lower() == ".mp4" else "video/x-msvideo"
    return FileResponse(
        path=safe_path,
        media_type=media_type,
        filename=safe_path.name,
    )


# ============================================================================
# Real-Time WebSocket Endpoint
# ============================================================================
@app.websocket("/api/ws/alerts")
async def websocket_alerts_endpoint(
    websocket: WebSocket,
    token: Optional[str] = Query(None),
) -> None:
    """WebSocket endpoint for real-time alert pushes to mobile apps."""
    expected_api = config.security.api_token
    expected_agent = config.security.agent_token

    if not token or token not in (expected_api, expected_agent):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await ws_manager.connect(websocket)
    try:
        # Keep connection alive and accept incoming pings
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)
    except Exception:
        ws_manager.disconnect(websocket)


# ============================================================================
# CLI Entry Point for Render
# ============================================================================
if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8000))
    logger.info("Starting RailGuard Vision API on 0.0.0.0:%d", port)
    uvicorn.run("app.api:app", host="0.0.0.0", port=port, reload=False)
