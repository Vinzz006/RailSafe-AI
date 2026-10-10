# RailSafe AI Backend - Docker Container for Google Cloud Run / Container Platforms
FROM python:3.11-slim

# Avoid writing .pyc files and buffer stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application and model directories
COPY app/ ./app/
COPY models/ ./models/

# Create non-root user for security
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

EXPOSE 8000

# Start Uvicorn production server
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
