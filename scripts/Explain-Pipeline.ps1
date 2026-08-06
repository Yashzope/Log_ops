# =============================================================================
# LogOps — Explain the live pipeline with real ClickHouse numbers
# Works against local Docker OR EC2 via SSH tunnel (localhost:8123).
#
#   .\scripts\Explain-Pipeline.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Get-EnvValue([string]$Key) {
    $line = Get-Content ".env" | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1)
}

function Invoke-CH([string]$Sql) {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:8123/" -Headers $script:headers -Method Post -Body $Sql -TimeoutSec 15
    return "$resp".Trim()
}

$chUser = Get-EnvValue "CLICKHOUSE_USER"
$chPass = Get-EnvValue "CLICKHOUSE_PASSWORD"
if (-not $chUser) { $chUser = "logops" }
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${chUser}:${chPass}"))
$script:headers = @{ Authorization = "Basic $b64" }

Write-Host ""
Write-Host "LogOps live pipeline walkthrough" -ForegroundColor Cyan
Write-Host @"

  [log-generator]  writes JSON + nginx logs
         |
  [Fluent Bit]     parses + Lua geo_country enrichment
         |
  [Kafka]          topic logops.raw.logs
         |
  [log-processor]  (local stand-in for Databricks Gold)
         |
  [ClickHouse]     raw_logs + metrics_5min
         |
  [Grafana]        dashboards

"@

try {
    $null = Invoke-CH "SELECT 1"
} catch {
    Write-Host "ClickHouse not reachable on localhost:8123" -ForegroundColor Red
    Write-Host "Start local lite stack OR run .\scripts\Open-Ec2-Tunnel.ps1 first."
    exit 1
}

$raw = Invoke-CH "SELECT count() FROM logops.raw_logs"
$met = Invoke-CH "SELECT count() FROM logops.metrics_5min"
$svc = Invoke-CH "SELECT service, count() c FROM logops.raw_logs GROUP BY service ORDER BY c DESC LIMIT 5 FORMAT TabSeparated"
$geo = Invoke-CH "SELECT geo_country, count() c FROM logops.raw_logs GROUP BY geo_country ORDER BY c DESC LIMIT 5 FORMAT TabSeparated"
$err = Invoke-CH "SELECT round(avg(error_rate_pct),2) FROM logops.metrics_5min"

Write-Host "1) Ingestion volume" -ForegroundColor Green
Write-Host "   raw_logs rows     : $raw"
Write-Host "   metrics_5min rows : $met"
Write-Host ""
Write-Host "2) Top services (proves generator diversity)" -ForegroundColor Green
Write-Host $svc
Write-Host ""
Write-Host "3) Geo enrichment from Fluent Bit Lua" -ForegroundColor Green
Write-Host $geo
Write-Host ""
Write-Host "4) Average error rate % across windows: $err" -ForegroundColor Green
Write-Host ""
Write-Host "Interview line:" -ForegroundColor Cyan
Write-Host " I built a medallion-style log pipeline: Fluent Bit to Kafka to analytics,"
Write-Host " with ClickHouse + Grafana SLIs, orchestrated for cloud with Airflow/Databricks/Terraform."
Write-Host ""
Write-Host "Open charts: http://localhost:3000/d/logops-overview/logops-overview"
