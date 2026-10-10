from datetime import datetime, timezone
import logging
from typing import Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.prediction import PredictionRequest, PredictionResponse, HealthResponse
from app.services.model_service import model_service
from app.security.firebase_auth import verify_firebase_token

logger = logging.getLogger("railsafe_backend.api")
router = APIRouter()

@router.get("/health", response_model=HealthResponse)
async def get_health():
    """
    Returns API health and ML model readiness. Does not expose sensitive server paths.
    """
    return HealthResponse(
        status="ok" if model_service.is_loaded else "degraded",
        model_loaded=model_service.is_loaded,
        model_version=model_service.model_version,
        model_name=model_service.model_name,
        features=model_service.expected_features,
    )

@router.post("/predict", response_model=PredictionResponse)
async def predict_telemetry(
    request: PredictionRequest,
    current_user: Dict[str, Any] = Depends(verify_firebase_token),
):
    """
    Performs server-side Random Forest ML inference on verified telemetry packets.
    Protected by Firebase Authentication ID token.
    """
    if not model_service.is_loaded:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Machine learning model is not ready or failed to initialize.",
        )

    user_id = current_user.get("uid", "anonymous")
    logger.info(
        f"[INFERENCE] Request for device={request.deviceId}, seq={request.sequence}, user={user_id}"
    )

    try:
        # Perform inference on exact training features: mq2, mq4, mq7
        inference_result = model_service.predict(
            mq2=request.sensors.mq2_raw,
            mq4=request.sensors.mq4_raw,
            mq7=request.sensors.mq7_raw,
        )

        return PredictionResponse(
            deviceId=request.deviceId,
            sequence=request.sequence,
            prediction=inference_result["prediction"],
            label=inference_result["label"],
            anomalyScore=inference_result["anomalyScore"],
            normalScore=inference_result["normalScore"],
            confidence=inference_result["confidence"],
            reviewRequired=inference_result["reviewRequired"],
            modelVersion=inference_result["modelVersion"],
            inferenceTimestamp=datetime.now(timezone.utc).isoformat(),
            inputFeatures=inference_result["inputFeatures"],
            userId=user_id,
        )
    except Exception as e:
        logger.error(f"[INFERENCE ERROR] {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Inference execution failed: {str(e)}",
        )
