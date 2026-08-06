-- =============================================================================
-- LogOps — Create quarantine_logs (Free Edition / if DLT table does not show)
-- Run in Databricks SQL Editor with your warehouse STARTED, then refresh Catalog.
-- =============================================================================

CREATE CATALOG IF NOT EXISTS logops;
CREATE SCHEMA IF NOT EXISTS logops.silver;

CREATE TABLE IF NOT EXISTS logops.silver.quarantine_logs (
  request_id STRING,
  event_time TIMESTAMP,
  ingestion_time TIMESTAMP,
  event_date DATE,
  service STRING,
  level STRING,
  message STRING,
  status_code INT,
  latency_ms DOUBLE,
  client_ip STRING,
  geo_country STRING,
  host STRING,
  raw_json STRING,
  quarantine_reason STRING,
  quarantined_at TIMESTAMP
) USING DELTA;

-- Sample bad rows (these are exactly what Silver would reject)
INSERT INTO logops.silver.quarantine_logs VALUES
(
  'bad-001',
  NULL,  -- invalid timestamp
  current_timestamp(),
  current_date(),
  'checkout',
  'INFO',
  'missing event_time',
  200,
  10.0,
  '10.0.0.9',
  'US',
  'api-1',
  '{}',
  'invalid_timestamp',
  current_timestamp()
),
(
  'bad-002',
  current_timestamp(),
  current_timestamp(),
  current_date(),
  'auth',
  'ERROR',
  'impossible status code',
  999,  -- invalid status
  50.0,
  '10.0.0.8',
  'IN',
  'api-2',
  '{}',
  'invalid_status_code',
  current_timestamp()
);

SELECT * FROM logops.silver.quarantine_logs;
