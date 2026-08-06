# =============================================================================
# LogOps — Dockerfile for the local Kafka → ClickHouse processor
# =============================================================================

FROM python:3.11-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY local_kafka_to_clickhouse.py .

ENV PYTHONUNBUFFERED=1 \
    MSK_BOOTSTRAP_SERVERS=kafka:29092 \
    KAFKA_TOPIC=logops.raw.logs \
    CLICKHOUSE_HOST=clickhouse \
    CLICKHOUSE_PORT=8123 \
    CLICKHOUSE_USER=logops

CMD ["python", "-u", "local_kafka_to_clickhouse.py"]
