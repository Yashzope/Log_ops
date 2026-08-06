# Databricks notebook source
# MAGIC %md
# MAGIC # LogOps — 01 Bronze Streaming
# MAGIC Reads raw logs from AWS MSK (Kafka), parses JSON, and writes a Delta Bronze table.
# MAGIC Widgets/parameters are filled by Airflow when the job is submitted.

# -----------------------------------------------------------------------------
# Import Spark / Delta helpers used throughout this notebook
# -----------------------------------------------------------------------------
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DoubleType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
import logging

# Configure a notebook-friendly logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("logops.bronze")

# Get (or create) the Spark session managed by Databricks
spark: SparkSession = SparkSession.builder.getOrCreate()

# -----------------------------------------------------------------------------
# Read notebook parameters (Airflow passes these; defaults help local runs)
# -----------------------------------------------------------------------------
dbutils.widgets.text("msk_bootstrap_servers", "[FILL_IN_YOUR_MSK_BROKER_URL]")
dbutils.widgets.text("kafka_topic", "logops.raw.logs")
dbutils.widgets.text("s3_bucket", "[FILL_IN_YOUR_S3_BUCKET_NAME]")
dbutils.widgets.text(
    "checkpoint_path",
    "s3://[FILL_IN_YOUR_S3_BUCKET_NAME]/checkpoints/bronze_raw_logs",
)

msk_bootstrap_servers = dbutils.widgets.get("msk_bootstrap_servers")
kafka_topic = dbutils.widgets.get("kafka_topic")
s3_bucket = dbutils.widgets.get("s3_bucket")
checkpoint_path = dbutils.widgets.get("checkpoint_path")

# Destination Delta table in Unity Catalog / Hive metastore style naming
BRONZE_TABLE = "logops.bronze.raw_logs"
BRONZE_PATH = f"s3://{s3_bucket}/delta/bronze/raw_logs"

# -----------------------------------------------------------------------------
# Define the expected JSON schema so bad fields fail clearly instead of silently
# -----------------------------------------------------------------------------
log_schema = StructType(
    [
        StructField("timestamp", StringType(), True),
        StructField("service", StringType(), True),
        StructField("level", StringType(), True),
        StructField("message", StringType(), True),
        StructField("status_code", IntegerType(), True),
        StructField("latency_ms", DoubleType(), True),
        StructField("client_ip", StringType(), True),
        StructField("geo_country", StringType(), True),
        StructField("request_id", StringType(), True),
        StructField("host", StringType(), True),
        StructField("pipeline", StringType(), True),
        StructField("remote", StringType(), True),
        StructField("method", StringType(), True),
        StructField("path", StringType(), True),
        StructField("code", StringType(), True),
    ]
)


def ensure_schemas() -> None:
    """Create catalog/schema objects if they do not exist yet."""
    spark.sql("CREATE CATALOG IF NOT EXISTS logops")
    spark.sql("CREATE SCHEMA IF NOT EXISTS logops.bronze")


def read_kafka_stream() -> DataFrame:
    """
    Start a structured streaming read from MSK Kafka.
    startingOffsets=latest avoids replaying the entire topic on first run.
    """
    return (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", msk_bootstrap_servers)
        .option("subscribe", kafka_topic)
        .option("startingOffsets", "latest")
        .option("failOnDataLoss", "false")
        .load()
    )


def parse_and_enrich(raw_df: DataFrame) -> DataFrame:
    """
    Convert Kafka binary value -> JSON columns, then add pipeline metadata.
    event_time = time from the log; ingestion_time = when Spark saw it.
    """
    json_df = raw_df.select(
        F.col("key").cast("string").alias("kafka_key"),
        F.col("topic").alias("kafka_topic"),
        F.col("partition").alias("kafka_partition"),
        F.col("offset").cast(LongType()).alias("kafka_offset"),
        F.col("timestamp").alias("kafka_timestamp"),
        F.from_json(F.col("value").cast("string"), log_schema).alias("data"),
        F.col("value").cast("string").alias("raw_json"),
    ).select("kafka_key", "kafka_topic", "kafka_partition", "kafka_offset", "kafka_timestamp", "data.*", "raw_json")

    # Prefer the nested timestamp string; fall back to Kafka record time
    return (
        json_df.withColumn(
            "event_time",
            F.coalesce(
                F.to_timestamp(F.col("timestamp")),
                F.col("kafka_timestamp"),
            ),
        )
        .withColumn("ingestion_time", F.current_timestamp())
        .withColumn("event_date", F.to_date(F.col("event_time")))
        .withColumn(
            "status_code",
            F.coalesce(F.col("status_code"), F.col("code").cast("int"), F.lit(0)),
        )
        .withColumn(
            "service",
            F.coalesce(F.col("service"), F.lit("unknown")),
        )
        .withColumn(
            "level",
            F.coalesce(F.col("level"), F.lit("INFO")),
        )
        .withColumn(
            "geo_country",
            F.coalesce(F.col("geo_country"), F.lit("ZZ")),
        )
    )


def write_bronze_stream(parsed_df: DataFrame):
    """
    Write the stream to Delta Lake with schema evolution and a checkpoint.
    checkpointLocation is mandatory for exactly-once streaming progress.
    """
    return (
        parsed_df.writeStream.format("delta")
        .option("checkpointLocation", checkpoint_path)
        .option("mergeSchema", "true")
        .outputMode("append")
        .partitionBy("event_date", "service")
        .trigger(processingTime="30 seconds")
        .table(BRONZE_TABLE)
    )


def main() -> None:
    """Orchestrate Bronze streaming with try/except so failures are logged clearly."""
    try:
        logger.info(
            "Starting Bronze stream from topic=%s brokers=%s",
            kafka_topic,
            msk_bootstrap_servers,
        )
        ensure_schemas()

        # Also register a path-based location for tools that prefer file paths
        spark.sql(
            f"""
            CREATE TABLE IF NOT EXISTS {BRONZE_TABLE}
            USING DELTA
            LOCATION '{BRONZE_PATH}'
            """
        )

        raw_stream = read_kafka_stream()
        parsed_stream = parse_and_enrich(raw_stream)
        query = write_bronze_stream(parsed_stream)

        # Await termination so the Databricks job stays alive while streaming
        query.awaitTermination()
    except Exception as exc:  # noqa: BLE001
        logger.exception("Bronze streaming failed: %s", exc)
        raise


# Run when the notebook / job is executed
main()
