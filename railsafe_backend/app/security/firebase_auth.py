import os
import logging
from typing import Optional, Dict, Any
from fastapi import Header, HTTPException, status
import firebase_admin
from firebase_admin import auth as fb_auth, credentials

logger = logging.getLogger("railsafe_backend.security")

# Initialize Firebase Admin SDK
_firebase_initialized = False

def initialize_firebase():
    global _firebase_initialized
    if _firebase_initialized or len(firebase_admin._apps) > 0:
        _firebase_initialized = True
        return

    cert_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "").strip()
    project_id = os.getenv("FIREBASE_PROJECT_ID", "railsafe-ai").strip()

    try:
        if cert_path and os.path.exists(cert_path):
            cred = credentials.Certificate(cert_path)
            firebase_admin.initialize_app(cred)
            logger.info(f"Firebase Admin SDK initialized with certificate: {cert_path}")
        else:
            # Attempts default Google Application Default Credentials (Cloud Run / GCP environment)
            firebase_admin.initialize_app(options={"projectId": project_id})
            logger.info(f"Firebase Admin SDK initialized with default credentials for project: {project_id}")
        _firebase_initialized = True
    except Exception as e:
        logger.warning(
            f"Firebase Admin SDK not initialized with production credentials: {e}. "
            f"If in development, ensure ALLOW_DEV_AUTH_BYPASS=true or set FIREBASE_SERVICE_ACCOUNT_PATH."
        )
        _firebase_initialized = False

# Run initial initialization attempt
initialize_firebase()

async def verify_firebase_token(
    authorization: Optional[str] = Header(None, description="Bearer <Firebase_ID_Token>")
) -> Dict[str, Any]:
    """
    Verifies Firebase Authentication ID token passed in HTTP Authorization header.
    Rejects missing, malformed, or expired tokens with HTTP 401.
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header. Please provide a Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Authorization header format. Expected: 'Bearer <token>'",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = parts[1].strip()
    allow_dev_bypass = os.getenv("ALLOW_DEV_AUTH_BYPASS", "false").lower() == "true"

    # Development / Testing mock token handling
    if allow_dev_bypass and token in ("DEMO_OFFICER_TOKEN", "dev-test-token", "test-valid-token"):
        return {
            "uid": "demo-officer-NDLS",
            "email": "demo.officer@railsafe.gov.in",
            "name": "Demo Officer (Development Bypass)",
            "role": "Screening Inspector",
            "auth_time": 1700000000,
        }

    # Production Firebase ID Token verification
    try:
        decoded_token = fb_auth.verify_id_token(token)
        return decoded_token
    except fb_auth.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has expired. Please refresh the authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except fb_auth.InvalidIdTokenError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Firebase ID token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Authentication token verification failed: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )
