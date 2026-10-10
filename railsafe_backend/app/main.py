import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("railsafe_backend")

from app.api.endpoints import router as api_router
from app.services.model_service import model_service
from app.security.firebase_auth import initialize_firebase

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("==================================================")
    logger.info(" Starting RailSafe AI Python Backend Server ")
    logger.info("==================================================")
    initialize_firebase()
    if model_service.is_loaded:
        logger.info(f"Model ready: {model_service.model_name} (v{model_service.model_version})")
    else:
        logger.warning("Model failed to load! Check MODEL_PATH environment setting.")
    yield
    logger.info("Shutting down RailSafe AI backend server.")

app = FastAPI(
    title="RailSafe AI — Telemetry Screening Backend",
    description="Python FastAPI backend providing secure edge machine learning inference for Indian Railways screening assistance.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None, # Disable Redoc in production
    lifespan=lifespan,
)

# Configure CORS
origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in origins if o.strip()],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Include routes at root and /api prefix
app.include_router(api_router)
app.include_router(api_router, prefix="/api")

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run("app.main:app", host=host, port=port, reload=True)
