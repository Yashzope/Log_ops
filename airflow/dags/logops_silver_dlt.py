# =============================================================================
# LogOps — Silver DLT DAG
# Triggers an existing Databricks Delta Live Tables pipeline (Run Now).
# =============================================================================

from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.databricks.operators.databricks import DatabricksRunNowOperator

from common_utils import sla_miss_callback, task_failure_callback

# Defaults: retry a couple of times and email on failure
default_args = {
    "owner": "logops",
    "depends_on_past": False,
    "email": [os.getenv("ALERT_EMAIL", "alerts@example.com")],
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=3),
    "sla": timedelta(minutes=45),
    "on_failure_callback": task_failure_callback,
}

with DAG(
    dag_id="logops_silver_dlt",
    description="Trigger Databricks Delta Live Tables pipeline for Silver clean_logs",
    default_args=default_args,
    start_date=datetime(2024, 1, 1),
    schedule_interval="15 */2 * * *",
    catchup=False,
    max_active_runs=1,
    sla_miss_callback=sla_miss_callback,
    tags=["logops", "silver", "dlt", "databricks"],
) as dag:

    # Job / pipeline ID created in the Databricks UI for the Silver DLT pipeline
    dlt_job_id = os.getenv("DATABRICKS_JOB_SILVER_DLT_ID", "0")

    # Run the pre-registered Databricks job that wraps the DLT pipeline
    run_silver_dlt = DatabricksRunNowOperator(
        task_id="run_silver_dlt_pipeline",
        databricks_conn_id=os.getenv("DATABRICKS_CONN_ID", "databricks_default"),
        job_id=int(dlt_job_id) if str(dlt_job_id).isdigit() else dlt_job_id,
        notebook_params={
            "source_table": "logops.bronze.raw_logs",
            "target_table": "logops.silver.clean_logs",
        },
        do_xcom_push=True,
    )

    run_silver_dlt
