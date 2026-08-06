# =============================================================================
# LogOps — Delta Lake maintenance DAG
# Runs OPTIMIZE + VACUUM against Bronze/Silver/Gold tables via Databricks REST.
# =============================================================================

from __future__ import annotations

import os
import time
from datetime import datetime, timedelta
from typing import Any

import requests
from airflow import DAG
from airflow.operators.python import PythonOperator

from common_utils import require_env, sla_miss_callback, task_failure_callback

default_args = {
    "owner": "logops",
    "depends_on_past": False,
    "email": [os.getenv("ALERT_EMAIL", "alerts@example.com")],
    "email_on_failure": True,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "sla": timedelta(hours=2),
    "on_failure_callback": task_failure_callback,
}

# Tables that should be compacted and vacuumed nightly
MAINTENANCE_TABLES = [
    "logops.bronze.raw_logs",
    "logops.silver.clean_logs",
    "logops.gold.metrics_5min",
]


def _databricks_headers(token: str) -> dict[str, str]:
    """Build HTTP headers for Databricks SQL Statement Execution API."""
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def run_sql_statement(host: str, token: str, warehouse_id: str, statement: str) -> dict[str, Any]:
    """
    Submit a SQL statement and poll until it succeeds or fails.
    Uses exponential-ish backoff between polls for beginner-friendly retries.
    """
    url = f"{host.rstrip('/')}/api/2.0/sql/statements"
    payload = {
        "warehouse_id": warehouse_id,
        "statement": statement,
        "wait_timeout": "0s",
    }

    response = requests.post(url, headers=_databricks_headers(token), json=payload, timeout=60)
    response.raise_for_status()
    statement_id = response.json()["statement_id"]

    status_url = f"{url}/{statement_id}"
    for attempt in range(1, 61):
        status_resp = requests.get(status_url, headers=_databricks_headers(token), timeout=30)
        status_resp.raise_for_status()
        body = status_resp.json()
        state = body.get("status", {}).get("state")

        if state == "SUCCEEDED":
            return body
        if state in {"FAILED", "CANCELED", "CLOSED"}:
            raise RuntimeError(f"SQL failed ({state}): {body}")

        # Back off slightly as we wait for long OPTIMIZE jobs
        time.sleep(min(5 + attempt, 30))

    raise TimeoutError(f"Timed out waiting for statement {statement_id}")


def optimize_and_vacuum(**_context: Any) -> str:
    """Run OPTIMIZE then VACUUM RETAIN 168 HOURS on each LogOps Delta table."""
    host = require_env("DATABRICKS_HOST")
    token = require_env("DATABRICKS_TOKEN")
    warehouse_id = require_env("DATABRICKS_SQL_WAREHOUSE_ID")

    results: list[str] = []
    for table in MAINTENANCE_TABLES:
        optimize_sql = f"OPTIMIZE {table}"
        vacuum_sql = f"VACUUM {table} RETAIN 168 HOURS"

        try:
            run_sql_statement(host, token, warehouse_id, optimize_sql)
            run_sql_statement(host, token, warehouse_id, vacuum_sql)
            results.append(f"OK:{table}")
        except Exception as exc:  # noqa: BLE001 — collect failures then raise
            results.append(f"FAIL:{table}:{exc}")
            raise RuntimeError(f"Maintenance failed for {table}: {exc}") from exc

    return "; ".join(results)


def mark_cold_archive_candidates(**_context: Any) -> str:
    """
    Move gold metrics older than 30 days into a Unity Catalog archive schema.

    Free Edition stand-in for cold tier:
      - Creates logops.archive.gold_metrics_cold (empty shell if missing)
      - INSERTs rows from logops.gold.metrics_5min older than 30 days

    AWS path note:
      S3 Glacier lifecycle on s3://{S3_BUCKET}/archive/ applies to objects
      copied under that prefix in full AWS deployments. Direct UC → S3
      external writes are often restricted on Free Edition, so this UC
      archive schema is the practical cold-tier stand-in. When credentials
      and external locations are available, copy Parquet under archive/
      so Glacier can age those objects.
    """
    host = require_env("DATABRICKS_HOST")
    token = require_env("DATABRICKS_TOKEN")
    warehouse_id = require_env("DATABRICKS_SQL_WAREHOUSE_ID")
    # Read for documentation / future AWS path (do not fail if unset on Free Edition)
    _bucket = os.getenv("S3_BUCKET", "")
    _region = os.getenv("AWS_REGION", "")

    stmts = [
        "CREATE SCHEMA IF NOT EXISTS logops.archive",
        (
            "CREATE TABLE IF NOT EXISTS logops.archive.gold_metrics_cold "
            "USING DELTA "
            "AS SELECT * FROM logops.gold.metrics_5min WHERE 1=0"
        ),
        (
            "INSERT INTO logops.archive.gold_metrics_cold "
            "SELECT * FROM logops.gold.metrics_5min "
            "WHERE event_time < current_timestamp() - INTERVAL 30 DAYS"
        ),
    ]

    for sql in stmts:
        run_sql_statement(host, token, warehouse_id, sql)

    note = (
        f"archived_to=logops.archive.gold_metrics_cold; "
        f"s3_glacier_prefix=s3://{_bucket}/archive/ region={_region}"
        if _bucket
        else "archived_to=logops.archive.gold_metrics_cold; S3_BUCKET unset"
    )
    return note


with DAG(
    dag_id="logops_maintenance",
    description="Nightly OPTIMIZE/VACUUM plus cold-archive candidate move",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 3 * * *",
    catchup=False,
    max_active_runs=1,
    sla_miss_callback=sla_miss_callback,
    tags=["logops", "maintenance", "delta"],
) as dag:

    # PythonOperator keeps dependencies light (requests already on the image)
    run_maintenance = PythonOperator(
        task_id="optimize_and_vacuum_delta_tables",
        python_callable=optimize_and_vacuum,
    )

    # Free Edition: UC archive schema; AWS: Glacier covers s3://bucket/archive/
    archive_cold = PythonOperator(
        task_id="mark_cold_archive_candidates",
        python_callable=mark_cold_archive_candidates,
    )

    run_maintenance >> archive_cold
