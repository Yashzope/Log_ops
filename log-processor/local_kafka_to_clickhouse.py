# =============================================================================
# LogOps — Local Kafka → ClickHouse bridge
# Replaces Databricks Gold for laptop demos so Grafana has live data.
# Reads JSON from Kafka, inserts into raw_logs, upserts simple 5-min metrics.
# =============================================================================

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any

import requests
from kafka import KafkaConsumer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("logops-local-processor")

_shutdown = False


def _handle_signal(signum: int, _frame: Any) -> None:
    """Allow Ctrl+C / docker stop to exit the poll loop cleanly."""
    global _shutdown
    logger.info("Signal %s received — shutting down", signum)
    _shutdown = True


def env(name: str, default: str = "") -> str:
    """Read an environment variable with a default."""
    return os.getenv(name, default).strip()


def clickhouse_query(sql: str, user: str, password: str, host: str, port: str) -> str:
    """Run one SQL statement against ClickHouse HTTP with basic retries."""
    url = f"http://{host}:{port}/"
    last_error: Exception | None = None
    for attempt in range(1, 6):
        try:
            response = requests.post(
                url,
                params={"database": "logops"},
                data=sql.encode("utf-8"),
                auth=(user, password),
                timeout=15,
            )
            response.raise_for_status()
            return response.text
        except requests.RequestException as exc:
            last_error = exc
            sleep_s = min(2**attempt, 20)
            logger.warning("ClickHouse query failed (attempt %s): %s", attempt, exc)
            time.sleep(sleep_s)
    raise RuntimeError(f"ClickHouse query failed after retries: {sql[:120]}") from last_error


def escape(value: str) -> str:
    """Escape a string for ClickHouse single-quoted literals."""
    return value.replace("\\", "\\\\").replace("'", "\\'")


def parse_event(raw: bytes) -> dict[str, Any] | None:
    """Turn one Kafka message into a normalized log dict."""
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        logger.warning("Skipping bad JSON: %s", exc)
        return None

    # Fluent Bit may wrap fields; accept both flat and nested shapes
    if "service" not in payload and isinstance(payload.get("message"), dict):
        payload = payload["message"]

    timestamp = payload.get("timestamp") or payload.get("time") or payload.get("date")
    if timestamp is None:
        timestamp = datetime.now(timezone.utc).isoformat()

    # Fluent Bit may emit epoch seconds (float/int) instead of an ISO string
    if isinstance(timestamp, (int, float)):
        dt = datetime.fromtimestamp(float(timestamp), tz=timezone.utc)
        ts_sql = dt.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    else:
        timestamp_str = str(timestamp)
        try:
            if timestamp_str.endswith("Z"):
                timestamp_str = timestamp_str.replace("Z", "+00:00")
            dt = datetime.fromisoformat(timestamp_str)
            ts_sql = dt.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        except ValueError:
            # nginx time format e.g. 28/Jul/2026:21:49:02 +0000
            try:
                dt = datetime.strptime(timestamp_str, "%d/%b/%Y:%H:%M:%S %z")
                ts_sql = dt.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
            except ValueError:
                ts_sql = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

    status = payload.get("status_code") or payload.get("code") or 0
    try:
        status_i = int(status)
    except (TypeError, ValueError):
        status_i = 0

    latency = payload.get("latency_ms") or 0.0
    try:
        latency_f = float(latency)
    except (TypeError, ValueError):
        latency_f = 0.0

    level = str(payload.get("level") or "INFO").upper()
    is_error = level in {"ERROR", "FATAL"} or status_i >= 500

    return {
        "timestamp": ts_sql,
        "service": str(payload.get("service") or "unknown"),
        "level": level,
        "message": str(payload.get("message") or ""),
        "status_code": status_i,
        "latency_ms": latency_f,
        "client_ip": str(payload.get("client_ip") or payload.get("remote") or "0.0.0.0"),
        "geo_country": str(payload.get("geo_country") or "ZZ"),
        "request_id": str(payload.get("request_id") or ""),
        "host": str(payload.get("host") or "local"),
        "raw_json": json.dumps(payload),
        "is_error": is_error,
    }


def insert_raw_batch(events: list[dict[str, Any]], **ch: str) -> None:
    """Insert a batch of events into logops.raw_logs."""
    if not events:
        return
    values = []
    for e in events:
        values.append(
            "("
            f"'{e['timestamp']}',"
            f"'{escape(e['service'])}',"
            f"'{escape(e['level'])}',"
            f"'{escape(e['message'])}',"
            f"{e['status_code']},"
            f"{e['latency_ms']},"
            f"'{escape(e['client_ip'])}',"
            f"'{escape(e['geo_country'])}',"
            f"'{escape(e['request_id'])}',"
            f"'{escape(e['host'])}',"
            f"'{escape(e['raw_json'])}'"
            ")"
        )
    sql = (
        "INSERT INTO logops.raw_logs "
        "(timestamp, service, level, message, status_code, latency_ms, "
        "client_ip, geo_country, request_id, host, raw_json) VALUES "
        + ",".join(values)
    )
    clickhouse_query(sql, **ch)


def flush_metrics(bucket: dict[tuple[str, str], dict[str, Any]], **ch: str) -> None:
    """
    Write simple 5-minute aggregates.
    Key = (window_start_sql, service). Values hold counters / latency list.
    """
    if not bucket:
        return
    values = []
    for (window_start, service), stats in bucket.items():
        # Window end = start + 5 minutes (string math avoided; use toDateTime math in SQL)
        req = stats["request_count"]
        err = stats["error_count"]
        latencies: list[float] = stats["latencies"]
        avg_lat = sum(latencies) / len(latencies) if latencies else 0.0
        sorted_lat = sorted(latencies)
        p95 = sorted_lat[int(0.95 * (len(sorted_lat) - 1))] if sorted_lat else 0.0
        err_pct = (err * 100.0 / req) if req else 0.0
        values.append(
            "("
            f"toDateTime('{window_start}'),"
            f"toDateTime('{window_start}') + INTERVAL 5 MINUTE,"
            f"'{escape(service)}',"
            f"{req},"
            f"{err},"
            f"{avg_lat},"
            f"{p95},"
            f"{err_pct}"
            ")"
        )
    sql = (
        "INSERT INTO logops.metrics_5min "
        "(window_start, window_end, service, request_count, error_count, "
        "avg_latency_ms, p95_latency_ms, error_rate_pct) VALUES "
        + ",".join(values)
    )
    clickhouse_query(sql, **ch)


def window_start_str(ts_sql: str) -> str:
    """Floor a 'YYYY-mm-dd HH:MM:SS.mmm' timestamp to a 5-minute bucket."""
    dt = datetime.strptime(ts_sql.split(".")[0], "%Y-%m-%d %H:%M:%S")
    floored_min = dt.minute - (dt.minute % 5)
    floored = dt.replace(minute=floored_min, second=0)
    return floored.strftime("%Y-%m-%d %H:%M:%S")


def main() -> int:
    """Poll Kafka forever and mirror events into ClickHouse."""
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    brokers = env("MSK_BOOTSTRAP_SERVERS", "kafka:29092")
    topic = env("KAFKA_TOPIC", "logops.raw.logs")
    ch = {
        "user": env("CLICKHOUSE_USER", "logops"),
        "password": env("CLICKHOUSE_PASSWORD", ""),
        "host": env("CLICKHOUSE_HOST", "clickhouse"),
        "port": env("CLICKHOUSE_PORT", "8123"),
    }

    logger.info("Connecting to Kafka %s topic=%s", brokers, topic)

    # Retry consumer creation until Kafka is ready
    consumer: KafkaConsumer | None = None
    while not _shutdown and consumer is None:
        try:
            consumer = KafkaConsumer(
                topic,
                bootstrap_servers=[b.strip() for b in brokers.split(",") if b.strip()],
                auto_offset_reset="earliest",
                enable_auto_commit=True,
                group_id="logops-local-processor",
                value_deserializer=lambda v: v,
                consumer_timeout_ms=1000,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Kafka not ready yet: %s — retrying", exc)
            time.sleep(5)

    assert consumer is not None
    logger.info("Processor started")

    batch: list[dict[str, Any]] = []
    metrics: dict[tuple[str, str], dict[str, Any]] = defaultdict(
        lambda: {"request_count": 0, "error_count": 0, "latencies": []}
    )
    last_flush = time.time()

    while not _shutdown:
        try:
            polled = consumer.poll(timeout_ms=1000)
            for _tp, records in polled.items():
                for record in records:
                    event = parse_event(record.value)
                    if event is None:
                        continue
                    batch.append(event)
                    key = (window_start_str(event["timestamp"]), event["service"])
                    metrics[key]["request_count"] += 1
                    if event["is_error"]:
                        metrics[key]["error_count"] += 1
                    metrics[key]["latencies"].append(event["latency_ms"])

            # Flush every 50 events or every 10 seconds
            if batch and (len(batch) >= 50 or time.time() - last_flush >= 10):
                insert_raw_batch(batch, **ch)
                flush_metrics(metrics, **ch)
                logger.info("Flushed %s events / %s metric buckets", len(batch), len(metrics))
                batch.clear()
                metrics.clear()
                last_flush = time.time()
        except Exception as exc:  # noqa: BLE001
            logger.exception("Processor loop error: %s", exc)
            time.sleep(3)

    # Final flush
    if batch:
        insert_raw_batch(batch, **ch)
        flush_metrics(metrics, **ch)
    consumer.close()
    logger.info("Processor stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
