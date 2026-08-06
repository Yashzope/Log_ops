-- =============================================================================
-- LogOps — Demo seed data for Grafana (optional)
-- Inserts synthetic 5-minute metrics so dashboards are not empty at first open.
-- =============================================================================

INSERT INTO logops.metrics_5min
(window_start, window_end, service, request_count, error_count, avg_latency_ms, p95_latency_ms, error_rate_pct)
SELECT
    toStartOfFiveMinutes(now() - toIntervalMinute(number * 5)) AS window_start,
    window_start + INTERVAL 5 MINUTE AS window_end,
    arrayElement(['payments-api', 'auth-service', 'inventory-api', 'checkout-ui', 'notifications'], (number % 5) + 1) AS service,
    toUInt64(80 + (number % 40)) AS request_count,
    toUInt64(number % 7) AS error_count,
    120.0 + (number % 50) AS avg_latency_ms,
    220.0 + (number % 80) AS p95_latency_ms,
    if(request_count = 0, 0.0, error_count * 100.0 / request_count) AS error_rate_pct
FROM numbers(60);

-- Raw demo rows via SELECT (more portable than VALUES + now())
INSERT INTO logops.raw_logs
(timestamp, service, level, message, status_code, latency_ms, client_ip, geo_country, request_id, host, raw_json)
SELECT now(), 'payments-api', 'INFO', 'Seeded demo payment authorized', 200, 95.5, '203.0.113.10', 'US', 'seed-req-1', 'seed', '{}';

INSERT INTO logops.raw_logs
(timestamp, service, level, message, status_code, latency_ms, client_ip, geo_country, request_id, host, raw_json)
SELECT now(), 'auth-service', 'WARN', 'Seeded demo slow login', 401, 340.2, '198.51.100.20', 'IN', 'seed-req-2', 'seed', '{}';

INSERT INTO logops.raw_logs
(timestamp, service, level, message, status_code, latency_ms, client_ip, geo_country, request_id, host, raw_json)
SELECT now(), 'inventory-api', 'ERROR', 'Seeded demo stock lookup failed', 500, 880.0, '192.0.2.30', 'GB', 'seed-req-3', 'seed', '{}';
