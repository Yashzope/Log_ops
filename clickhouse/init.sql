-- =============================================================================
-- LogOps — ClickHouse initialization script
-- Runs once when the ClickHouse container starts (mounted into init folder).
-- Creates the analytics database plus raw and aggregated log tables.
-- =============================================================================

-- Create a dedicated database so LogOps tables stay separate from defaults
CREATE DATABASE IF NOT EXISTS logops;

-- ---------------------------------------------------------------------------
-- raw_logs: high-volume event store for recent individual log lines.
-- Engine = MergeTree: ClickHouse's default fast columnar table engine.
-- PARTITION BY toDate(timestamp): keeps each day in its own folder on disk.
-- ORDER BY (service, timestamp): speeds up filters like "service X in last hour".
-- TTL timestamp + INTERVAL 7 DAY: auto-deletes rows older than 7 days.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS logops.raw_logs
(
    -- When the event happened in the source system
    timestamp DateTime64(3),

    -- Which microservice or app produced the log (e.g. payments-api)
    service LowCardinality(String),

    -- Log severity: DEBUG, INFO, WARN, ERROR
    level LowCardinality(String),

    -- Human-readable message body
    message String,

    -- HTTP status code when the log is request-related (0 if not applicable)
    status_code UInt16,

    -- Request duration in milliseconds (0 if not a timed request)
    latency_ms Float64,

    -- Client IP address as text
    client_ip String,

    -- Mock country code added by Fluent Bit Lua enrichment (e.g. US, IN)
    geo_country LowCardinality(String),

    -- Trace/correlation id for joining related events
    request_id String,

    -- Host that wrote the log file
    host LowCardinality(String),

    -- Raw JSON payload kept for debugging / reprocessing
    raw_json String
)
ENGINE = MergeTree
PARTITION BY toDate(timestamp)
ORDER BY (service, timestamp)
-- DateTime64 cannot be used directly in TTL on this CH version — cast to DateTime
TTL toDateTime(timestamp) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- ---------------------------------------------------------------------------
-- metrics_5min: rolled-up counters every 5 minutes for dashboards.
-- Much smaller than raw_logs, so we keep it longer (30 days).
-- ORDER BY (window_start, service): matches how Grafana usually queries.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS logops.metrics_5min
(
    -- Start of the 5-minute aggregation window
    window_start DateTime,

    -- End of the 5-minute aggregation window
    window_end DateTime,

    -- Service the metrics belong to
    service LowCardinality(String),

    -- Total number of requests/events in the window
    request_count UInt64,

    -- How many of those events were errors
    error_count UInt64,

    -- Average latency in milliseconds
    avg_latency_ms Float64,

    -- 95th percentile latency in milliseconds
    p95_latency_ms Float64,

    -- Error rate as a percentage (0–100)
    error_rate_pct Float64
)
ENGINE = MergeTree
PARTITION BY toDate(window_start)
ORDER BY (window_start, service)
TTL window_start + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;
