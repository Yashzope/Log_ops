# =============================================================================
# LogOps — Open SSH tunnels to EC2 UIs (campus/firewall friendly)
# Browse http://localhost:3000 (Grafana) and http://localhost:8081 (Kafka UI)
#
#   .\scripts\Open-Ec2-Tunnel.ps1
# Keep the window open while using the UIs. Ctrl+C to stop.
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Get-EnvValue([string]$Key) {
    $line = Get-Content ".env" -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "^$([regex]::Escape($Key))=" } |
        Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1)
}

$pem = Get-EnvValue "EC2_SSH_KEY_PATH"
if (-not $pem -or -not (Test-Path $pem)) {
    $pem = Join-Path $env:USERPROFILE "logops-key.pem"
}
if (-not (Test-Path $pem)) { throw "PEM not found at $pem" }

$ec2Ip = Get-EnvValue "EC2_PUBLIC_IP"
if (-not $ec2Ip -or $ec2Ip.StartsWith("[FILL_IN")) {
    Push-Location "aws-infra"
    $ec2Ip = terraform output -raw ec2_public_ip
    Pop-Location
}

Write-Host ""
Write-Host "Tunneling to $ec2Ip" -ForegroundColor Cyan
Write-Host "  Grafana : http://localhost:3000   (user=admin, password in .env GRAFANA_ADMIN_PASSWORD)"
Write-Host "  Kafka UI: http://localhost:8081"
Write-Host "  ClickHouse: http://localhost:8123"
Write-Host ""
Write-Host "Leave this window open. Press Ctrl+C to close."
Write-Host ""

Start-Process "http://localhost:3000/d/logops-overview/logops-overview"
Start-Process "http://localhost:8081"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes `
  -i $pem `
  -L 3000:127.0.0.1:3000 `
  -L 8081:127.0.0.1:8081 `
  -L 8123:127.0.0.1:8123 `
  "ec2-user@$ec2Ip" -N
