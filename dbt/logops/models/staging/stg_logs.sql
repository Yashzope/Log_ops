-- =============================================================================
-- LogOps — staging model over Silver clean_logs
-- Incremental merge keeps only new/changed request_ids for faster rebuilds.
-- =============================================================================

{{
  config(
    materialized='incremental',
    unique_key='request_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    tags=['staging', 'logops']
  )
}}

-- Read curated Silver logs from Delta Lake
with source as (
    select
        request_id,
        event_time,
        ingestion_time,
        event_date,
        service,
        level,
        message,
        status_code,
        latency_ms,
        client_ip,
        geo_country,
        host,
        is_error,
        performance_tier,
        status_category,
        processed_at
    from {{ source('silver', 'clean_logs') }}
    {% if is_incremental() %}
    -- Only pull rows newer than what we already loaded
    where event_time > (select coalesce(max(event_time), cast('1970-01-01' as timestamp)) from {{ this }})
    {% endif %}
),

-- Light renaming / casting so marts see a stable contract
renamed as (
    select
        request_id,
        cast(event_time as timestamp) as event_time,
        cast(ingestion_time as timestamp) as ingestion_time,
        cast(event_date as date) as event_date,
        lower(service) as service,
        upper(level) as level,
        message,
        cast(status_code as int) as status_code,
        cast(latency_ms as double) as latency_ms,
        client_ip,
        upper(geo_country) as geo_country,
        host,
        cast(is_error as boolean) as is_error,
        performance_tier,
        status_category,
        cast(processed_at as timestamp) as processed_at
    from source
    where request_id is not null
)

select * from renamed
