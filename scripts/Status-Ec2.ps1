# =============================================================================
# LogOps — Quick EC2 status (SSH + compose + optional local tunnel check)
#
#   .\scripts\Status-Ec2.ps1
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
if (-not $pem -or -not (Test-Path $pem)) { $pem = Join-Path $env:USERPROFILE "logops-key.pem" }
$ec2Ip = Get-EnvValue "EC2_PUBLIC_IP"
if (-not $ec2Ip -or $ec2Ip.StartsWith("[FILL_IN")) {
    Push-Location "aws-infra"
    $ec2Ip = terraform output -raw ec2_public_ip
    Pop-Location
}

Write-Host "EC2=$ec2Ip" -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i $pem "ec2-user@$ec2Ip" "cd /opt/logops && sudo docker compose -f docker-compose.lite.yml ps"

Write-Host ""
Write-Host "Local tunnel check:"
try {
    $h = Invoke-RestMethod "http://127.0.0.1:3000/api/health" -TimeoutSec 3
    Write-Host "  Grafana tunnel OK ($($h.version))" -ForegroundColor Green
} catch {
    Write-Host "  Grafana tunnel DOWN - run .\scripts\Open-Ec2-Tunnel.ps1" -ForegroundColor Yellow
}
