# Databricks notebook source
# MAGIC %md
# MAGIC # LogOps — 03 Gold Aggregations
# MAGIC Builds 5-minute window metrics from Silver and dual-writes to Delta + ClickHouse.

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.utils import AnalysisException
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("logops.gold")

spark: SparkSession = SparkSession.builder.getOrCreate()

# -----------------------------------------------------------------------------
# Notebook parameters (Airflow / job bindings)
# -----------------------------------------------------------------------------
dbutils.widgets.text("silver_table", "logops.silver.clean_logs")
dbutils.widgets.text("gold_table", "logops.gold.metrics_5min")
dbutils.widgets.text("clickhouse_host", "[FILL_IN_YOUR_CLICKHOUSE_HOST]")
dbutils.widgets.text("clickhouse_port", "8123")
dbutils.widgets.text("clickhouse_user", "logops")
dbutils.widgets.text("clickhouse_password", "[FILL_IN_YOUR_CLICKHOUSE_PASSWORD]")
dbutils.widgets.text("clickhouse_db", "logops")
dbutils.widgets.text("clickhouse_table", "metrics_5min")
dbutils.widgets.text("s3_bucket", "[FILL_IN_YOUR_S3_BUCKET_NAME]")
dbutils.widgets.text("checkpoint_path", "")

silver_table = dbutils.widgets.get("silver_table")
gold_table = dbutils.widgets.get("gold_table")
ch_host = dbutils.widgets.get("clickhouse_host")
ch_port = dbutils.widgets.get("clickhouse_port")
ch_user = dbutils.widgets.get("clickhouse_user")
ch_password = dbutils.widgets.get("clickhouse_password")
ch_db = dbutils.widgets.get("clickhouse_db")
ch_table = dbutils.widgets.get("clickhouse_table")
s3_bucket = dbutils.widgets.get("s3_bucket")
checkpoint_path = dbutils.widgets.get("checkpoint_path") or (
    f"s3://{s3_bucket}/checkpoints/gold_metrics_5min"
)

GOLD_PATH = f"s3://{s3_bucket}/delta/gold/metrics_5min"


def ensure_gold_objects() -> None:
    """Create gold schema and empty Delta table if missing."""
    spark.sql("CREATE SCHEMA IF NOT EXISTS logops.gold")
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {gold_table} (
          window_start TIMESTAMP,
          window_end TIMESTAMP,
          service STRING,
          request_count BIGINT,
          error_count BIGINT,
          avg_latency_ms DOUBLE,
          p95_latency_ms DOUBLE,
          error_rate_pct DOUBLE
        ) USING DELTA
        LOCATION '{GOLD_PATH}'
        """
    )


def read_silver_stream() -> DataFrame:
    """Read Silver as a stream so we can do watermarked window aggregations."""
    return (
        spark.readStream.format("delta")
        .table(silver_table)
        .withWatermark("event_time", "10 minutes")
    )


def aggregate_5min(silver_df: DataFrame) -> DataFrame:
    """Compute per-service metrics over tumbling 5-minute windows."""
    return (
        silver_df.groupBy(
            F.window(F.col("event_time"), "5 minutes").alias("w"),
            F.col("service"),
        )
        .agg(
            F.count(F.lit(1)).alias("request_count"),
            F.sum(F.when(F.col("is_error") == True, 1).otherwise(0)).alias("error_count"),
            F.avg("latency_ms").alias("avg_latency_ms"),
            F.expr("percentile_approx(latency_ms, 0.95)").alias("p95_latency_ms"),
        )
        .select(
            F.col("w.start").alias("window_start"),
            F.col("w.end").alias("window_end"),
            "service",
            "request_count",
            "error_count",
            "avg_latency_ms",
            "p95_latency_ms",
            (
                F.when(F.col("request_count") == 0, F.lit(0.0)).otherwise(
                    F.col("error_count") * 100.0 / F.col("request_count")
                )
            ).alias("error_rate_pct"),
        )
    )


def write_to_clickhouse(batch_df: DataFrame, batch_id: int) -> None:
    """
    Sink one micro-batch to ClickHouse over JDBC with retry/backoff.
    Uses the ClickHouse JDBC URL form: jdbc:clickhouse://host:port/db
    """
    if batch_df.rdd.isEmpty():
        logger.info("Batch %s empty — skipping ClickHouse write", batch_id)
        return

    jdbc_url = f"jdbc:clickhouse://{ch_host}:{ch_port}/{ch_db}"
    props = {
        "user": ch_user,
        "password": ch_password,
        "driver": "com.clickhouse.jdbc.ClickHouseDriver",
    }

    last_error: Exception | None = None
    for attempt in range(1, 6):
        try:
            (
                batch_df.write.mode("append")
                .option("batchsize", 1000)
                .option("isolationLevel", "NONE")
                .jdbc(url=jdbc_url, table=ch_table, properties=props)
            )
            logger.info("Batch %s written to ClickHouse on attempt %s", batch_id, attempt)
            return
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            sleep_s = min(2 ** attempt, 30)
            logger.warning(
                "ClickHouse write failed (batch=%s attempt=%s): %s — retry in %ss",
                batch_id,
                attempt,
                exc,
                sleep_s,
            )
            time.sleep(sleep_s)

    raise RuntimeError(f"ClickHouse sink failed for batch {batch_id}") from last_error


def foreach_batch_dual_write(batch_df: DataFrame, batch_id: int) -> None:
    """Write each micro-batch to Delta Gold AND ClickHouse."""
    try:
        (
            batch_df.write.format("delta")
            .mode("append")
            .option("mergeSchema", "true")
            .saveAsTable(gold_table)
        )
        write_to_clickhouse(batch_df, batch_id)
    except AnalysisException as exc:
        logger.exception("Delta write failed for batch %s: %s", batch_id, exc)
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("Gold dual-write failed for batch %s: %s", batch_id, exc)
        raise


def main() -> None:
    """Start the Gold streaming aggregation job."""
    try:
        ensure_gold_objects()
        silver_stream = read_silver_stream()
        metrics_stream = aggregate_5min(silver_stream)

        query = (
            metrics_stream.writeStream.foreachBatch(foreach_batch_dual_write)
            .option("checkpointLocation", checkpoint_path)
            .outputMode("update")
            .trigger(processingTime="1 minute")
            .start()
        )
        query.awaitTermination()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Gold aggregations failed: %s", exc)
        raise


main()
