# =============================================================================
# LogOps - Create / reset Superset admin from .env values
# =============================================================================

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Get-EnvValue($Key) {
    $match = Get-Content (Join-Path $Root ".env") | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($match) { return $match.Substring($Key.Length + 1).Trim() }
    return ""
}

$user = Get-EnvValue "SUPERSET_ADMIN_USER"
$pass = Get-EnvValue "SUPERSET_ADMIN_PASSWORD"
$email = Get-EnvValue "SUPERSET_ADMIN_EMAIL"
if (-not $user) { $user = "admin" }
if (-not $email) { $email = "admin@logops.demo" }
if (-not $pass) { throw "SUPERSET_ADMIN_PASSWORD is missing in .env" }

$running = docker ps --filter "name=logops-superset" --filter "status=running" --format "{{.Names}}"
if (-not $running) {
    throw "logops-superset is not running. Start the full stack first: .\scripts\Start-Local.ps1"
}

Write-Host "Initializing Superset admin user '$user' ..."
cmd /c "docker exec logops-superset superset db upgrade"
if ($LASTEXITCODE -ne 0) { throw "superset db upgrade failed" }

cmd /c "docker exec logops-superset superset fab create-admin --username $user --firstname Admin --lastname LogOps --email $email --password $pass"
cmd /c "docker exec logops-superset superset fab reset-password --username $user --password $pass"
cmd /c "docker exec logops-superset superset init"
if ($LASTEXITCODE -ne 0) { throw "superset init failed" }

Write-Host ""
Write-Host "Open http://localhost:8088"
Write-Host "Username: $user"
Write-Host "Password: value of SUPERSET_ADMIN_PASSWORD in .env"
