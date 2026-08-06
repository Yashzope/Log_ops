# Databricks notebook source
# MAGIC %md
# MAGIC # LogOps — 02 Silver Delta Live Tables
# MAGIC Cleans Bronze logs with data-quality expectations and derived columns.
# MAGIC Deploy this file as a **DLT / Lakeflow pipeline** notebook (not a normal Job notebook).
# MAGIC
# MAGIC ## After you re-import this file
# MAGIC 1. Open **Workflows → Pipelines** → your `logops-silver` pipeline
# MAGIC 2. Confirm **Source** points to **this** notebook (not an old copy)
# MAGIC 3. Click **Full refresh all** (or Full refresh) then **Start**
# MAGIC 4. When the run is green, open the pipeline **Tables** tab — you should see:
# MAGIC    - `clean_logs`
# MAGIC    - `quarantine_logs`
# MAGIC 5. In **Catalog**, look under the pipeline **target catalog.schema**
# MAGIC    (often `logops.silver` if you set that as the target)
# MAGIC
# MAGIC If Bronze `logops.bronze.raw_logs` is missing, the pipeline fails and
# MAGIC **no new tables appear**. Create Bronze first, or run
# MAGIC `05_create_quarantine_for_demo.sql` in the SQL Editor for a demo table.

# -----------------------------------------------------------------------------
# Delta Live Tables imports
# -----------------------------------------------------------------------------
import dlt
from pyspark.sql import functions as F


# -----------------------------------------------------------------------------
# Optional Bronze mirror inside the same DLT pipeline (reads UC Bronze table)
# -----------------------------------------------------------------------------
@dlt.view(
    name="bronze_raw_logs_vw",
    comment="View over the managed Bronze Delta table for Silver expectations",
)
def bronze_raw_logs_vw():
    """Read already-landed Bronze data as the DLT source view."""
    return spark.read.table("logops.bronze.raw_logs")


# -----------------------------------------------------------------------------
# Silver live table: validated, enriched logs for analytics
# -----------------------------------------------------------------------------
@dlt.table(
    name="clean_logs",
    comment="Silver cleaned logs with quality expectations and derived fields",
    table_properties={
        "quality": "silver",
        "pipelines.autoOptimize.zOrderCols": "service,event_time",
    },
)
# Drop rows that cannot be time-ordered (hard expectation)
@dlt.expect_or_drop("valid_timestamp", "event_time IS NOT NULL")
# Keep only plausible HTTP status codes (or zero for non-HTTP events)
@dlt.expect_or_drop(
    "valid_status_code",
    "status_code IS NULL OR (status_code >= 0 AND status_code < 600)",
)
# Warn (but keep) unexpected log levels so we can spot schema drift
@dlt.expect(
    "valid_level",
    "level IN ('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')",
)
def clean_logs():
    """Apply expectations and add derived columns used by Gold / dashboards."""
    bronze = dlt.read("bronze_raw_logs_vw")

    return (
        bronze.withColumn(
            "is_error",
            F.when(
                (F.col("level").isin("ERROR", "FATAL"))
                | (F.col("status_code") >= 500),
                F.lit(True),
            ).otherwise(F.lit(False)),
        )
        .withColumn(
            "performance_tier",
            F.when(F.col("latency_ms").isNull(), F.lit("unknown"))
            .when(F.col("latency_ms") < 100, F.lit("fast"))
            .when(F.col("latency_ms") < 500, F.lit("normal"))
            .when(F.col("latency_ms") < 2000, F.lit("slow"))
            .otherwise(F.lit("critical")),
        )
        .withColumn(
            "status_category",
            F.when(F.col("status_code") < 100, F.lit("n/a"))
            .when(F.col("status_code") < 200, F.lit("informational"))
            .when(F.col("status_code") < 300, F.lit("success"))
            .when(F.col("status_code") < 400, F.lit("redirect"))
            .when(F.col("status_code") < 500, F.lit("client_error"))
            .otherwise(F.lit("server_error")),
        )
        .withColumn("processed_at", F.current_timestamp())
        .select(
            "event_time",
            "ingestion_time",
            "event_date",
            "service",
            "level",
            "message",
            "status_code",
            "latency_ms",
            "client_ip",
            "geo_country",
            "request_id",
            "host",
            "is_error",
            "performance_tier",
            "status_category",
            "processed_at",
            "raw_json",
        )
    )


# -----------------------------------------------------------------------------
# Quarantine table: rows that fail hard expectations (for inspection)
# -----------------------------------------------------------------------------
# clean_logs above uses expect_or_drop — bad rows never reach Silver.
# This table keeps those same failures so you can inspect / fix / reprocess them.
# Hard rules (must match the expect_or_drop predicates above):
#   - event_time IS NULL
#   - status_code outside [0, 600)
@dlt.table(
    name="quarantine_logs",
    comment="Rows failing hard Silver expectations, kept for inspection",
    table_properties={"quality": "quarantine"},
)
def quarantine_logs():
    """Capture invalid Bronze rows that clean_logs drops, with a reason column."""
    bronze = dlt.read("bronze_raw_logs_vw")

    # Same hard filters as expect_or_drop on clean_logs
    bad = bronze.filter(
        F.col("event_time").isNull()
        | (
            F.col("status_code").isNotNull()
            & ((F.col("status_code") < 0) | (F.col("status_code") >= 600))
        )
    )

    return (
        bad.withColumn(
            "quarantine_reason",
            F.when(F.col("event_time").isNull(), F.lit("invalid_timestamp"))
            .when(
                F.col("status_code").isNotNull()
                & ((F.col("status_code") < 0) | (F.col("status_code") >= 600)),
                F.lit("invalid_status_code"),
            )
            .otherwise(F.lit("unknown")),
        )
        .withColumn("quarantined_at", F.current_timestamp())
    )
