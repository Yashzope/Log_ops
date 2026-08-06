# =============================================================================
# LogOps — Fake log generator
# Writes JSON app logs and nginx-style access logs for Fluent Bit to tail.
# Designed for beginners: clear comments, graceful Ctrl+C, safe retries.
# =============================================================================

from __future__ import annotations

import json
import logging
import os
import random
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from faker import Faker

# Configure simple logging so container logs explain what the script is doing
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("logops-generator")

# Fake data factory used for IPs, paths, messages, etc.
fake = Faker()

# Global flag flipped by Ctrl+C / docker stop so the loop can exit cleanly
_shutdown_requested = False

# Sample microservices that will appear in generated logs
SERVICES = [
    "payments-api",
    "auth-service",
    "inventory-api",
    "checkout-ui",
    "notifications",
]

# Log levels with weights so INFO is common and ERROR is rarer
LEVELS = ["DEBUG", "INFO", "WARN", "ERROR"]
LEVEL_WEIGHTS = [10, 60, 20, 10]

# HTTP status codes with weights (mostly 200s)
STATUS_CODES = [200, 201, 301, 400, 401, 403, 404, 500, 502, 503]
STATUS_WEIGHTS = [55, 10, 5, 8, 5, 3, 7, 4, 2, 1]


def _handle_signal(signum: int, _frame: Any) -> None:
    """Mark shutdown so the infinite loop exits after the current write."""
    global _shutdown_requested
    logger.info("Received signal %s — shutting down gracefully...", signum)
    _shutdown_requested = True


def ensure_log_dir(log_dir: Path) -> None:
    """Create the log directory if it does not already exist."""
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        logger.error("Could not create log directory %s: %s", log_dir, exc)
        raise


def build_app_log() -> dict[str, Any]:
    """Build one structured JSON application log event."""
    service = random.choice(SERVICES)
    level = random.choices(LEVELS, weights=LEVEL_WEIGHTS, k=1)[0]
    status_code = random.choices(STATUS_CODES, weights=STATUS_WEIGHTS, k=1)[0]
    latency_ms = round(random.lognormvariate(3.5, 0.6), 2)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": service,
        "level": level,
        "message": fake.sentence(nb_words=8),
        "status_code": status_code,
        "latency_ms": latency_ms,
        "client_ip": fake.ipv4_public(),
        "request_id": fake.uuid4(),
        "host": "log-generator",
    }


def build_nginx_line() -> str:
    """Build one nginx combined-format access log line."""
    remote = fake.ipv4_public()
    user = "-"
    now = datetime.now(timezone.utc).strftime("%d/%b/%Y:%H:%M:%S +0000")
    method = random.choice(["GET", "POST", "PUT", "DELETE"])
    path = random.choice(
        ["/health", "/api/v1/orders", "/api/v1/users", "/login", "/checkout", "/static/app.js"]
    )
    code = random.choices(STATUS_CODES, weights=STATUS_WEIGHTS, k=1)[0]
    size = random.randint(200, 50000)
    referer = fake.uri()
    agent = fake.user_agent()
    return (
        f'{remote} - {user} [{now}] "{method} {path} HTTP/1.1" '
        f'{code} {size} "{referer}" "{agent}"\n'
    )


def append_line(path: Path, line: str, retries: int = 3) -> None:
    """Append one line to a file with simple retry on transient IO errors."""
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with path.open("a", encoding="utf-8") as handle:
                handle.write(line)
                handle.flush()
            return
        except OSError as exc:
            last_error = exc
            logger.warning(
                "Write failed for %s (attempt %s/%s): %s",
                path,
                attempt,
                retries,
                exc,
            )
            time.sleep(0.5 * attempt)
    raise RuntimeError(f"Failed writing to {path}") from last_error


def write_once(app_log_path: Path, nginx_log_path: Path) -> None:
    """Write one app JSON log and one nginx access log line."""
    app_event = build_app_log()
    append_line(app_log_path, json.dumps(app_event) + "\n")
    append_line(nginx_log_path, build_nginx_line())


def main() -> int:
    """Run forever until Ctrl+C / SIGTERM, writing logs with random sleep."""
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    log_dir = Path(os.getenv("LOG_DIR", "/var/log/logops"))
    sleep_min = float(os.getenv("SLEEP_MIN_SECONDS", "0.5"))
    sleep_max = float(os.getenv("SLEEP_MAX_SECONDS", "2.0"))

    ensure_log_dir(log_dir)
    app_log_path = log_dir / "app_logs.json"
    nginx_log_path = log_dir / "nginx_access.log"

    logger.info("Writing logs to %s (Ctrl+C to stop)", log_dir)
    written = 0

    while not _shutdown_requested:
        try:
            write_once(app_log_path, nginx_log_path)
            written += 1
            if written % 50 == 0:
                logger.info("Generated %s log pairs so far", written)
        except Exception as exc:  # noqa: BLE001 — keep the loop alive on errors
            logger.exception("Unexpected error while writing logs: %s", exc)
            time.sleep(2)
            continue

        # Sleep a random amount so traffic looks more realistic
        time.sleep(random.uniform(sleep_min, sleep_max))

    logger.info("Shutdown complete after writing %s log pairs", written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
