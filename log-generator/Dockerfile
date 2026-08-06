# =============================================================================
# LogOps — Dockerfile for the fake log generator
# Uses a small Python image so the container stays lightweight.
# =============================================================================

FROM python:3.11-slim

# Fail fast on errors in shell form RUN instructions
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Create a non-root user for safer runtime
RUN useradd --create-home --shell /bin/bash logops

WORKDIR /app

# Install only the Python dependencies we need
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the generator script into the image
COPY generate_logs.py .

# Default log directory (also mounted as a volume from compose)
RUN mkdir -p /var/log/logops && chown -R logops:logops /var/log/logops /app

USER logops

ENV LOG_DIR=/var/log/logops \
    SLEEP_MIN_SECONDS=0.5 \
    SLEEP_MAX_SECONDS=2.0 \
    PYTHONUNBUFFERED=1

# Run the infinite log writer
CMD ["python", "-u", "generate_logs.py"]
