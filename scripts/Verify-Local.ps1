# =============================================================================
# LogOps — Verify the local lite pipeline is healthy
# Checks containers, ClickHouse row growth, Grafana health, and processor flushes.
# Does not print passwords.
#
#   .\scripts\Verify-Local.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$failures = 0

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

function Pass($Message) { Write-Host "  PASS - $Message" -ForegroundColor Green }
function Fail($Message) { Write-Host "  FAIL - $Message" -ForegroundColor Red; $script:failures++ }

function Get-EnvValue([string]$Key) {
    $line = Get-Content ".env" -ErrorAction SilentlyContinue | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1)
}

if (-not (Test-Path ".env")) {
    throw "Missing .env - run .\scripts\Start-Lite.ps1 first"
}

# Detect which compose file is active
$composeArgs = @("-f", "docker-compose.lite.yml")
$psOut = docker compose @composeArgs ps --format json 2>$null
if (-not $psOut) {
    $composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.local-kafka.yml")
}

Write-Log "Checking containers..."
$required = @("logops-kafka", "logops-clickhouse", "logops-log-generator", "logops-fluent-bit", "logops-log-processor", "logops-grafana")
foreach ($name in $required) {
    $status = docker inspect --format '{{.State.Status}}' $name 2>$null
    if ($status -eq "running") { Pass "$name is running" } else { Fail "$name status=$status" }
}

Write-Log "Checking ClickHouse data..."
$chUser = Get-EnvValue "CLICKHOUSE_USER"
$chPass = Get-EnvValue "CLICKHOUSE_PASSWORD"
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${chUser}:${chPass}"))
try {
    $raw = Invoke-RestMethod -Uri "http://localhost:8123/" -Headers @{ Authorization = "Basic $b64" } -Method Post -Body "SELECT count() FROM logops.raw_logs"
    $met = Invoke-RestMethod -Uri "http://localhost:8123/" -Headers @{ Authorization = "Basic $b64" } -Method Post -Body "SELECT count() FROM logops.metrics_5min"
    if ([int]$raw -gt 0) { Pass "raw_logs count=$raw" } else { Fail "raw_logs is empty" }
    if ([int]$met -gt 0) { Pass "metrics_5min count=$met" } else { Fail "metrics_5min is empty" }
} catch {
    Fail "ClickHouse query failed: $($_.Exception.Message)"
}

Write-Log "Checking Grafana..."
try {
    $health = Invoke-RestMethod "http://localhost:3000/api/health"
    if ($health.database -eq "ok") { Pass "Grafana database=ok version=$($health.version)" } else { Fail "Grafana unhealthy" }
} catch {
    Fail "Grafana not reachable"
}

Write-Log "Checking processor recent activity..."
$procLogs = cmd /c "docker logs logops-log-processor --tail 50 2>&1"
if ($procLogs -match "Flushed") { Pass "log-processor has flushed batches" } else { Fail "No Flushed lines in processor logs" }
if ($procLogs -match "Traceback|Processor loop error") {
    Write-Host "  WARN - processor logs show loop errors; inspect: docker logs logops-log-processor" -ForegroundColor Yellow
}

Write-Host ""
if ($failures -gt 0) {
    Write-Log "Verify finished with $failures failure(s)"
    exit 1
}
Write-Log "All local checks passed"
Write-Host "Open UIs: .\scripts\Open-Local.ps1"
