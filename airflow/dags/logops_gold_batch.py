# =============================================================================
# LogOps — Gold batch aggregations DAG
# Prefers Run Now on a pre-created Databricks Job (Free Edition / serverless).
# Falls back to Submit Run only if DATABRICKS_JOB_GOLD_ID is missing.
# =============================================================================

from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.databricks.operators.databricks import (
    DatabricksRunNowOperator,
    DatabricksSubmitRunOperator,
)

from common_utils import sla_miss_callback, task_failure_callback

default_args = {
    "owner": "logops",
    "depends_on_past": False,
    "email": [os.getenv("ALERT_EMAIL", "alerts@example.com")],
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "sla": timedelta(minutes=40),
    "on_failure_callback": task_failure_callback,
}

DATABRICKS_CONN_ID = os.getenv("DATABRICKS_CONN_ID", "databricks_default")
GOLD_JOB_ID = os.getenv("DATABRICKS_JOB_GOLD_ID", "0")
NOTEBOOK_PATH = os.getenv(
    "DATABRICKS_GOLD_NOTEBOOK_PATH",
    "/Workspace/logops/03_gold_aggregations",
)
EXISTING_CLUSTER_ID = os.getenv("DATABRICKS_EXISTING_CLUSTER_ID", "")

NOTEBOOK_PARAMS = {
    "silver_table": "logops.silver.clean_logs",
    "gold_table": "logops.gold.metrics_5min",
    "clickhouse_host": os.getenv("CLICKHOUSE_HOST", "clickhouse"),
    "clickhouse_port": os.getenv("CLICKHOUSE_PORT", "8123"),
    "clickhouse_user": os.getenv("CLICKHOUSE_USER", "logops"),
    "clickhouse_password": os.getenv("CLICKHOUSE_PASSWORD", ""),
    "clickhouse_db": "logops",
    "clickhouse_table": "metrics_5min",
    "s3_bucket": os.getenv("S3_BUCKET", ""),
}

with DAG(
    dag_id="logops_gold_batch",
    description="Trigger Databricks Gold aggregations notebook + ClickHouse sink",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="*/15 * * * *",
    catchup=False,
    max_active_runs=1,
    sla_miss_callback=sla_miss_callback,
    tags=["logops", "gold", "batch", "databricks", "clickhouse"],
) as dag:

    if GOLD_JOB_ID and GOLD_JOB_ID.isdigit() and int(GOLD_JOB_ID) > 0:
        run_gold = DatabricksRunNowOperator(
            task_id="run_gold_job",
            databricks_conn_id=DATABRICKS_CONN_ID,
            job_id=int(GOLD_JOB_ID),
            notebook_params=NOTEBOOK_PARAMS,
            do_xcom_push=True,
        )
    else:
        if EXISTING_CLUSTER_ID and not EXISTING_CLUSTER_ID.startswith("[FILL_IN"):
            cluster_config: dict = {"existing_cluster_id": EXISTING_CLUSTER_ID}
        else:
            cluster_config = {
                "new_cluster": {
                    "spark_version": "13.3.x-scala2.12",
                    "node_type_id": "i3.xlarge",
                    "num_workers": 2,
                    "spark_conf": {
                        "spark.databricks.delta.preview.enabled": "true",
                    },
                }
            }

        run_gold = DatabricksSubmitRunOperator(
            task_id="submit_gold_aggregations",
            databricks_conn_id=DATABRICKS_CONN_ID,
            json={
                **cluster_config,
                "notebook_task": {
                    "notebook_path": NOTEBOOK_PATH,
                    "base_parameters": NOTEBOOK_PARAMS,
                },
                "timeout_seconds": 2400,
            },
            do_xcom_push=True,
        )

    run_gold
