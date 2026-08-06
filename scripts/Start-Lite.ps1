# =============================================================================
# LogOps — Fastest local demo (Windows): lite stack only
# Skips Airflow/Superset/MinIO so first success is quicker.
#
#   .\scripts\Start-Lite.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Install and start Docker Desktop first."
}

$EnvFile = Join-Path $RootDir ".env"
if (-not (Test-Path $EnvFile)) {
    Copy-Item (Join-Path $RootDir ".env.local.example") $EnvFile
    Write-Log "Created .env from .env.local.example"
}

# Ensure passwords exist even if user never ran Generate-Secrets
$raw = Get-Content $EnvFile -Raw
if ($raw -match 'FILL_IN_YOUR_CLICKHOUSE_PASSWORD|change_me') {
    & (Join-Path $PSScriptRoot "Generate-Secrets.ps1")
}

Write-Log "Starting LITE stack (Kafka → ClickHouse → Grafana)..."
docker compose -f docker-compose.lite.yml up -d --build

Write-Log "Waiting 30s for first logs to flow..."
Start-Sleep -Seconds 30
docker compose -f docker-compose.lite.yml ps

function Get-EnvValue($Key) {
    $match = Get-Content $EnvFile | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($match) { return $match.Substring($Key.Length + 1) }
    return ""
}

$gUser = Get-EnvValue "GRAFANA_ADMIN_USER"
$gPass = Get-EnvValue "GRAFANA_ADMIN_PASSWORD"
$chUser = Get-EnvValue "CLICKHOUSE_USER"
$chPass = Get-EnvValue "CLICKHOUSE_PASSWORD"

Write-Host ""
Write-Host "===== Lite demo ready =====" -ForegroundColor Cyan
Write-Host "Grafana  http://localhost:3000  ($gUser / $gPass)"
Write-Host "Kafka UI http://localhost:8081"
Write-Host "ClickHouse ping: http://localhost:8123/ping"
Write-Host ""
Write-Host "Quick query (PowerShell):"
Write-Host "  Invoke-RestMethod -Uri 'http://localhost:8123/' -Headers @{Authorization=('Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('${chUser}:${chPass}')))} -Method Post -Body 'SELECT count() FROM logops.raw_logs'"
Write-Host ""
Write-Host "Stop: docker compose -f docker-compose.lite.yml down"
