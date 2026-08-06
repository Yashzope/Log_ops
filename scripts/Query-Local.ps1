# =============================================================================
# LogOps — Run sample ClickHouse analytics queries (local demo)
# Prints beginner-friendly results from live data. Does not print passwords.
#
#   .\scripts\Query-Local.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Get-EnvValue([string]$Key) {
    $line = Get-Content ".env" | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1)
}

function Invoke-CH([string]$Sql, [string]$Title) {
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host $Sql -ForegroundColor DarkGray
    $result = Invoke-RestMethod -Uri "http://localhost:8123/" -Headers $script:headers -Method Post -Body $Sql
    Write-Host $result
}

$chUser = Get-EnvValue "CLICKHOUSE_USER"
$chPass = Get-EnvValue "CLICKHOUSE_PASSWORD"
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${chUser}:${chPass}"))
$script:headers = @{ Authorization = "Basic $b64" }

Invoke-CH "SELECT count() AS raw_events FROM logops.raw_logs" "Total raw events"
Invoke-CH "SELECT count() AS metric_rows FROM logops.metrics_5min" "Total metric rows"
Invoke-CH @"
SELECT
  service,
  sum(request_count) AS requests,
  round(avg(error_rate_pct), 2) AS avg_error_pct,
  round(avg(p95_latency_ms), 2) AS avg_p95_ms
FROM logops.metrics_5min
GROUP BY service
ORDER BY requests DESC
LIMIT 5
FORMAT TabSeparatedWithNames
"@ "Top services by request volume"
Invoke-CH @"
SELECT
  toStartOfHour(window_start) AS hour,
  sum(request_count) AS requests,
  sum(error_count) AS errors
FROM logops.metrics_5min
GROUP BY hour
ORDER BY hour DESC
LIMIT 12
FORMAT TabSeparatedWithNames
"@ "Hourly request / error trend"
Invoke-CH @"
SELECT
  geo_country,
  count() AS events,
  countIf(level = 'ERROR') AS errors
FROM logops.raw_logs
GROUP BY geo_country
ORDER BY events DESC
LIMIT 10
FORMAT TabSeparatedWithNames
"@ "Events by geo_country (Fluent Bit Lua enrichment)"

Write-Host ""
Write-Host "Tip: open Grafana for charts - .\scripts\Open-Local.ps1"
