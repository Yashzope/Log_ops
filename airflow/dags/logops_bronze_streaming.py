# =============================================================================
# LogOps — Bronze streaming DAG
# Prefers Run Now on a pre-created Databricks Job (Free Edition / serverless).
# Falls back to Submit Run only if DATABRICKS_JOB_BRONZE_ID is missing.
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
    "max_retry_delay": timedelta(minutes=15),
    "sla": timedelta(hours=1),
    "on_failure_callback": task_failure_callback,
}

NOTEBOOK_PATH = os.getenv(
    "DATABRICKS_BRONZE_NOTEBOOK_PATH",
    "/Workspace/logops/01_bronze_streaming",
)
EXISTING_CLUSTER_ID = os.getenv("DATABRICKS_EXISTING_CLUSTER_ID", "")
MSK_BOOTSTRAP_SERVERS = os.getenv("MSK_BOOTSTRAP_SERVERS", "")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "logops.raw.logs")
S3_BUCKET = os.getenv("S3_BUCKET", "")
DATABRICKS_CONN_ID = os.getenv("DATABRICKS_CONN_ID", "databricks_default")
BRONZE_JOB_ID = os.getenv("DATABRICKS_JOB_BRONZE_ID", "0")

NOTEBOOK_PARAMS = {
    "msk_bootstrap_servers": MSK_BOOTSTRAP_SERVERS,
    "kafka_topic": KAFKA_TOPIC,
    "s3_bucket": S3_BUCKET,
    "checkpoint_path": f"s3://{S3_BUCKET}/checkpoints/bronze_raw_logs",
}

with DAG(
    dag_id="logops_bronze_streaming",
    description="Trigger Databricks Bronze Kafka -> Delta streaming notebook",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 */6 * * *",
    catchup=False,
    max_active_runs=1,
    sla_miss_callback=sla_miss_callback,
    tags=["logops", "bronze", "streaming", "databricks"],
) as dag:

    # Free Edition path: trigger the Job you created in Databricks UI (serverless OK)
    if BRONZE_JOB_ID and BRONZE_JOB_ID.isdigit() and int(BRONZE_JOB_ID) > 0:
        run_bronze = DatabricksRunNowOperator(
            task_id="run_bronze_job",
            databricks_conn_id=DATABRICKS_CONN_ID,
            job_id=int(BRONZE_JOB_ID),
            notebook_params=NOTEBOOK_PARAMS,
            do_xcom_push=True,
        )
    else:
        # Paid workspace fallback: submit a one-off run (needs classic/job cluster)
        if EXISTING_CLUSTER_ID and not EXISTING_CLUSTER_ID.startswith("[FILL_IN"):
            cluster_config: dict = {"existing_cluster_id": EXISTING_CLUSTER_ID}
        else:
            cluster_config = {
                "new_cluster": {
                    "spark_version": "13.3.x-scala2.12",
                    "node_type_id": "i3.xlarge",
                    "num_workers": 2,
                    "aws_attributes": {"availability": "ON_DEMAND"},
                    "spark_conf": {
                        "spark.databricks.delta.preview.enabled": "true",
                    },
                }
            }

        run_bronze = DatabricksSubmitRunOperator(
            task_id="submit_bronze_streaming",
            databricks_conn_id=DATABRICKS_CONN_ID,
            json={
                **cluster_config,
                "notebook_task": {
                    "notebook_path": NOTEBOOK_PATH,
                    "base_parameters": NOTEBOOK_PARAMS,
                },
                "timeout_seconds": 3600,
            },
            do_xcom_push=True,
        )

    run_bronze
