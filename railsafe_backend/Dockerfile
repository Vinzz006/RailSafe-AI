# ==============================================================================
# RailSafe AI — ML Inference Backend Container
# Production-ready Dockerfile for Local Testing, Google Cloud Run, and Kubernetes
# ==============================================================================

FROM python:3.11-slim

# Prevent Python from writing .pyc files and buffer stdout/stderr for real-time logging
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000 \
    ENVIRONMENT=production \
    MODEL_PATH=models/railsafe_rf_model.pkl

# Create non-root user and group early for least-privilege security
RUN groupadd -g 10001 appuser && \
    useradd -u 10001 -g appuser -s /bin/bash -m appuser

WORKDIR /app

# Install runtime system packages (curl for container health checks)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Layer 1: Copy and install Python dependencies (cached if requirements.txt unchanged)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Layer 2: Copy application code and trained ML models with non-root ownership
COPY --chown=appuser:appuser app/ ./app/
COPY --chown=appuser:appuser models/ ./models/

# Switch to non-root user
USER appuser

# Document exposed default port
EXPOSE 8000

# Container Healthcheck (polls /health endpoint using curl)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT:-8000}/health || exit 1

# Production ASGI Entry Point:
# Uses 'sh -c exec' to dynamically bind to the platform-provided $PORT (e.g. Cloud Run)
# 'exec' replaces the shell with the uvicorn process (PID 1) for graceful SIGTERM/SIGINT shutdown
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1 --timeout-keep-alive 65"]
