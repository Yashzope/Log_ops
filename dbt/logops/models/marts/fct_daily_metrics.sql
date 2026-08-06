-- =============================================================================
-- LogOps — daily fact metrics mart
-- One row per service per day for executive / interview-friendly dashboards.
-- =============================================================================

{{
  config(
    materialized='table',
    tags=['marts', 'logops']
  )
}}

-- Aggregate staging logs to daily service-level metrics
with daily as (
    select
        event_date,
        service,
        count(*) as request_count,
        sum(case when is_error then 1 else 0 end) as error_count,
        avg(latency_ms) as avg_latency_ms,
        approx_percentile(latency_ms, 0.95) as p95_latency_ms,
        sum(case when status_category = 'server_error' then 1 else 0 end) as server_error_count,
        count(distinct geo_country) as country_count
    from {{ ref('stg_logs') }}
    group by 1, 2
)

select
    event_date,
    service,
    request_count,
    error_count,
    avg_latency_ms,
    p95_latency_ms,
    server_error_count,
    country_count,
    case
        when request_count = 0 then 0.0
        else (error_count * 100.0) / request_count
    end as error_rate_pct,
    current_timestamp() as dbt_updated_at
from daily
