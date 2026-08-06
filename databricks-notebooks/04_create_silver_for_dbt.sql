-- =============================================================================
-- LogOps — Create Silver table so dbt can run (Databricks Free Edition friendly)
-- Run this in Databricks: SQL Editor → New query → paste → Run
-- =============================================================================

-- 1) Catalog + schemas
CREATE CATALOG IF NOT EXISTS logops;
CREATE SCHEMA IF NOT EXISTS logops.bronze;
CREATE SCHEMA IF NOT EXISTS logops.silver;
CREATE SCHEMA IF NOT EXISTS logops.gold;
CREATE SCHEMA IF NOT EXISTS logops.dbt;

-- 2) Silver table expected by dbt (source: logops.silver.clean_logs)
CREATE TABLE IF NOT EXISTS logops.silver.clean_logs (
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
  is_error BOOLEAN,
  performance_tier STRING,
  status_category STRING,
  processed_at TIMESTAMP,
  raw_json STRING
) USING DELTA;

-- 3) Sample rows (enough for dbt staging + daily metrics)
INSERT INTO logops.silver.clean_logs VALUES
(
  'req-001',
  current_timestamp() - INTERVAL 2 HOURS,
  current_timestamp() - INTERVAL 2 HOURS,
  current_date(),
  'checkout',
  'INFO',
  'order placed',
  200,
  85.0,
  '10.0.0.1',
  'US',
  'api-1',
  false,
  'fast',
  'success',
  current_timestamp(),
  '{}'
),
(
  'req-002',
  current_timestamp() - INTERVAL 1 HOURS,
  current_timestamp() - INTERVAL 1 HOURS,
  current_date(),
  'checkout',
  'ERROR',
  'payment failed',
  500,
  1200.0,
  '10.0.0.2',
  'IN',
  'api-1',
  true,
  'slow',
  'server_error',
  current_timestamp(),
  '{}'
),
(
  'req-003',
  current_timestamp() - INTERVAL 30 MINUTES,
  current_timestamp() - INTERVAL 30 MINUTES,
  current_date(),
  'auth',
  'WARN',
  'slow login',
  200,
  450.0,
  '10.0.0.3',
  'GB',
  'api-2',
  false,
  'normal',
  'success',
  current_timestamp(),
  '{}'
);

-- 4) Verify
SELECT COUNT(*) AS row_count FROM logops.silver.clean_logs;
SELECT * FROM logops.silver.clean_logs LIMIT 10;
