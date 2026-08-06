# =============================================================================
# LogOps — Redeploy lite stack to the existing EC2 host
# Requires: terraform already applied, working PEM at EC2_SSH_KEY_PATH
#
#   .\scripts\Deploy-Lite-Ec2.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

function Get-EnvValue([string]$Key) {
    $line = Get-Content ".env" | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1)
}

$pem = Get-EnvValue "EC2_SSH_KEY_PATH"
if (-not $pem -or $pem.StartsWith("[FILL_IN") -or -not (Test-Path $pem)) {
    $pem = Join-Path $env:USERPROFILE "logops-key.pem"
}
if (-not (Test-Path $pem)) { throw "PEM not found: $pem" }

$ec2Ip = Get-EnvValue "EC2_PUBLIC_IP"
if (-not $ec2Ip -or $ec2Ip.StartsWith("[FILL_IN")) {
    Push-Location "aws-infra"
    $ec2Ip = terraform output -raw ec2_public_ip
    Pop-Location
}

Write-Log "Target EC2 $ec2Ip"

# Keep .env in sync
(Get-Content .env) | ForEach-Object {
    if ($_ -match '^EC2_PUBLIC_IP=') { "EC2_PUBLIC_IP=$ec2Ip" }
    elseif ($_ -match '^MSK_BOOTSTRAP_SERVERS=') { "MSK_BOOTSTRAP_SERVERS=kafka:29092" }
    elseif ($_ -match '^EC2_SSH_KEY_PATH=') { "EC2_SSH_KEY_PATH=$pem" }
    else { $_ }
} | Set-Content .env -Encoding UTF8

$sshBase = @("-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-i", $pem, "ec2-user@$ec2Ip")

Write-Log "Checking SSH..."
ssh @sshBase "echo SSH_OK" | Out-Host

$zip = Join-Path $RootDir "logops-lite-deploy.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path @(
    "docker-compose.lite.yml", "clickhouse", "fluent-bit", "log-generator",
    "log-processor", "grafana", "scripts", ".env"
) -DestinationPath $zip -Force

Write-Log "Uploading package..."
scp @("-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-i", $pem) $zip "ec2-user@${ec2Ip}:/home/ec2-user/logops-lite-deploy.zip"

Write-Log "Remote compose up..."
ssh @sshBase "sudo mkdir -p /opt/logops && sudo chown ec2-user:ec2-user /opt/logops && cd /opt/logops && unzip -o ~/logops-lite-deploy.zip -d /opt/logops && sed -i 's/\r`$//' clickhouse/apply-init.sh && sudo docker compose -f docker-compose.lite.yml up -d --build && sudo docker compose -f docker-compose.lite.yml ps"

Write-Host ""
Write-Host "Grafana : http://$ec2Ip`:3000" -ForegroundColor Cyan
Write-Host "Kafka UI: http://$ec2Ip`:8081"
Write-Host "SSH     : ssh -i `"$pem`" ec2-user@$ec2Ip"
