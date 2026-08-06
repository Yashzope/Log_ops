# =============================================================================
# LogOps — Print local URLs and open Grafana/Kafka UI in the browser
# Does not print passwords; copies Grafana password to clipboard instead.
#
#   .\scripts\Open-Local.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $RootDir ".env"

function Get-EnvValue([string]$Key) {
    $line = Get-Content $EnvFile | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1)
}

if (-not (Test-Path $EnvFile)) {
    throw "Missing .env - run .\scripts\Start-Lite.ps1 first"
}

$gUser = Get-EnvValue "GRAFANA_ADMIN_USER"
$gPass = Get-EnvValue "GRAFANA_ADMIN_PASSWORD"

Write-Host ""
Write-Host "LogOps local UIs" -ForegroundColor Cyan
Write-Host "  Grafana : http://localhost:3000   (user=$gUser)"
Write-Host "  Kafka UI: http://localhost:8081"
Write-Host "  ClickHouse ping: http://localhost:8123/ping"
Write-Host ""
Write-Host "Grafana password copied to clipboard (from .env)."
Set-Clipboard -Value $gPass

Start-Process "http://localhost:3000/d/logops-overview/logops-overview"
Start-Process "http://localhost:8081"

Write-Host "Paste the password on the Grafana login form (Ctrl+V)."
