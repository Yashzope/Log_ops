# LogOps — NASA-HTTP log replayer (stdlib only)
FROM python:3.11-slim

WORKDIR /app
COPY replay_nasa.py .

ENV NASA_LOG_PATH=/data/nasa/NASA_access_log_Jul95.gz
ENV LOG_DIR=/var/log/logops
ENV SLEEP_SECONDS=0.05
ENV LOOP=true
ENV SYNTHETIC_LATENCY=true

CMD ["python", "-u", "replay_nasa.py"]
