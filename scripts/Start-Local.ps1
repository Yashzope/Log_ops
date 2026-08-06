# =============================================================================
# LogOps - One-command local demo (Windows PowerShell)
# Starts: local Kafka + generator + Fluent Bit + processor + ClickHouse + Grafana
# (+ full Airflow stack from the main compose file).
#
# Prerequisites: Docker Desktop running
# Usage:
#   cd C:\Users\91741\Downloads\logops
#   .\scripts\Start-Local.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker not found. Install Docker Desktop, start it, then re-run."
}

cmd /c "docker info >NUL 2>&1"
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop does not look running. Start it and wait until it is healthy."
}

$EnvFile = Join-Path $RootDir ".env"
$LocalExample = Join-Path $RootDir ".env.local.example"

if (-not (Test-Path $EnvFile)) {
    if (Test-Path $LocalExample) {
        Copy-Item $LocalExample $EnvFile
        Write-Log "Created .env from .env.local.example"
    } else {
        Copy-Item (Join-Path $RootDir ".env.example") $EnvFile
        Write-Log "Created .env from .env.example"
    }
}

$lines = Get-Content $EnvFile
$lines = $lines | ForEach-Object {
    if ($_ -match '^MSK_BOOTSTRAP_SERVERS=') { 'MSK_BOOTSTRAP_SERVERS=kafka:29092' }
    elseif ($_ -match '^KAFKA_TOPIC=') { 'KAFKA_TOPIC=logops.raw.logs' }
    else { $_ }
}
$lines | Set-Content $EnvFile -Encoding UTF8

$needsSecrets = Select-String -Path $EnvFile -Pattern 'FILL_IN_YOUR_|will_be_replaced|change_me' -Quiet
if ($needsSecrets) {
    Write-Log "Refreshing secrets..."
    & (Join-Path $PSScriptRoot "Generate-Secrets.ps1")
    $lines = Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^MSK_BOOTSTRAP_SERVERS=') { 'MSK_BOOTSTRAP_SERVERS=kafka:29092' } else { $_ }
    }
    $lines | Set-Content $EnvFile -Encoding UTF8
}

$lines = Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^AIRFLOW_UID=') { 'AIRFLOW_UID=50000' } else { $_ }
}
$lines | Set-Content $EnvFile -Encoding UTF8

Write-Log "Stopping lite/NASA stack if present (frees ports)..."
cmd /c "docker compose -f docker-compose.lite.yml -f docker-compose.nasa.yml down"

Write-Log "Starting LogOps local stack (compose + local Kafka)..."
cmd /c "docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml up -d --build"
if ($LASTEXITCODE -ne 0) {
    throw "docker compose failed (exit $LASTEXITCODE). Often a Docker Hub pull/TLS issue on campus Wi-Fi. Retry, or pull images one-by-one, then re-run."
}

Write-Log "Waiting 25s for services to settle..."
Start-Sleep -Seconds 25

Write-Log "Compose status:"
cmd /c "docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml ps"

$airflowUp = @(docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml ps --status running --services 2>$null)
if ($airflowUp -notcontains "airflow-webserver") {
    Write-Host "WARNING: airflow-webserver is not running yet. Check: docker logs logops-airflow-webserver" -ForegroundColor Yellow
}

function Get-EnvValue($Key) {
    $match = Get-Content $EnvFile | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($match) { return $match.Substring($Key.Length + 1) }
    return ""
}

$grafanaUser = Get-EnvValue "GRAFANA_ADMIN_USER"
$grafanaPass = Get-EnvValue "GRAFANA_ADMIN_PASSWORD"
$airflowUser = Get-EnvValue "AIRFLOW_ADMIN_USER"
$airflowPass = Get-EnvValue "AIRFLOW_ADMIN_PASSWORD"

Write-Host ""
Write-Host "===== LogOps local demo is starting =====" -ForegroundColor Cyan
Write-Host "Grafana : http://localhost:3000   user=$grafanaUser  pass=$grafanaPass"
Write-Host "Airflow : http://localhost:8080   user=$airflowUser  pass=$airflowPass"
Write-Host "Kafka UI: http://localhost:8081"
Write-Host "ClickHouse HTTP: http://localhost:8123"
Write-Host "Superset: http://localhost:8088"
Write-Host ""
Write-Host "Pipeline: log-generator -> Fluent Bit -> Kafka -> log-processor -> ClickHouse -> Grafana"
Write-Host "Open Grafana -> Dashboards -> LogOps Overview (may take 1-2 minutes to show live points)."
Write-Host ""
Write-Host "Stop later with:" -ForegroundColor Yellow
Write-Host "  docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml down"
