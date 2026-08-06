# =============================================================================
# LogOps - Start lite stack with NASA-HTTP as the log source
# =============================================================================

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Gz = Join-Path $Root "data\nasa\NASA_access_log_Jul95.gz"
$Sample = Join-Path $Root "data\nasa\sample_jul95.log"

if (-not (Test-Path $Gz) -and -not (Test-Path $Sample)) {
    Write-Host "NASA dataset missing - downloading..."
    & (Join-Path $PSScriptRoot "Download-Nasa.ps1")
}

# Prefer full July gz; fall back to sample for smoke demos
if (Test-Path $Gz) {
    $env:NASA_LOG_PATH = "/data/nasa/NASA_access_log_Jul95.gz"
    Write-Host "Using full NASA July 1995 gz"
} else {
    $env:NASA_LOG_PATH = "/data/nasa/sample_jul95.log"
    Write-Host "Using sample_jul95.log (run Download-Nasa.ps1 for the full file)"
}

# Free ports if the full Airflow stack is still up.
# Docker prints progress on stderr; do not treat that as a terminating error.
Write-Host "Stopping full stack if present (ignore errors if already stopped)..."
cmd /c "docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml down"

Write-Host "Starting lite stack with NASA-HTTP replayer..."
# Use cmd so Docker's stderr progress lines do not become PowerShell terminating errors
cmd /c "docker compose -f docker-compose.lite.yml -f docker-compose.nasa.yml up -d --build"
if ($LASTEXITCODE -ne 0) {
    throw "docker compose failed (exit $LASTEXITCODE). Is Docker Desktop running? Try running the same docker compose command again."
}

Write-Host ""
Write-Host "NASA-HTTP -> Fluent Bit -> Kafka -> ClickHouse -> Grafana"
Write-Host "  Grafana:  http://localhost:3000"
Write-Host "  Kafka UI: http://localhost:8081"
Write-Host "Source: https://ita.ee.lbl.gov/html/contrib/NASA-HTTP.html"
Write-Host ""
Write-Host "Verify:  .\scripts\Verify-Local.ps1"
Write-Host "Stop:    docker compose -f docker-compose.lite.yml -f docker-compose.nasa.yml down"
