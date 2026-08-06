# =============================================================================
# LogOps — Windows helper: package project and print EC2 deploy commands
# Full bash deploy.sh needs SSH/rsync from Git Bash or WSL. This script:
#   1) Ensures secrets/.env exist
#   2) Runs terraform apply
#   3) Builds a deploy tarball
#   4) Prints exact scp/ssh commands for beginners on Windows
# =============================================================================

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $RootDir "aws-infra"
$EnvFile = Join-Path $RootDir ".env"

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

if (-not (Test-Path $EnvFile)) {
    Write-Log ".env missing — running Generate-Secrets.ps1 first"
    & (Join-Path $PSScriptRoot "Generate-Secrets.ps1")
}

# Load simple KEY=VALUE pairs from .env into process env
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $parts = $_.Split("=", 2)
    if ($parts.Count -eq 2) {
        [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
    }
}

$keyPath = $env:EC2_SSH_KEY_PATH
if (-not $keyPath -or $keyPath.StartsWith("[FILL_IN")) {
    throw "Set EC2_SSH_KEY_PATH in .env to your .pem file path"
}
if (-not (Test-Path $keyPath)) {
    throw "SSH key not found: $keyPath"
}

$tfvars = Join-Path $TfDir "terraform.tfvars"
if (-not (Test-Path $tfvars)) {
    throw "Missing aws-infra/terraform.tfvars — copy from terraform.tfvars.example and fill values"
}

Set-Location $TfDir
Write-Log "terraform init + apply"
terraform init -input=false
if (Test-Path "tfplan") {
    terraform apply -input=false tfplan
} else {
    terraform apply -input=false -auto-approve
}

$ec2Ip = terraform output -raw ec2_public_ip
$msk = terraform output -raw msk_bootstrap_brokers
$bucket = terraform output -raw s3_bucket_name

Write-Log "EC2=$ec2Ip"
Write-Log "MSK=$msk"
Write-Log "S3=$bucket"

# Patch .env with Terraform outputs
$envText = Get-Content $EnvFile
$envText = $envText | ForEach-Object {
    if ($_ -match '^MSK_BOOTSTRAP_SERVERS=') { "MSK_BOOTSTRAP_SERVERS=$msk" }
    elseif ($_ -match '^S3_BUCKET=') { "S3_BUCKET=$bucket" }
    elseif ($_ -match '^EC2_PUBLIC_IP=') { "EC2_PUBLIC_IP=$ec2Ip" }
    else { $_ }
}
$envText | Set-Content $EnvFile -Encoding UTF8

# Create a tarball-like zip for scp (Windows-friendly)
$zipPath = Join-Path $RootDir "logops-deploy.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Write-Log "Creating $zipPath"
Compress-Archive -Path (
    Get-ChildItem $RootDir -Force |
    Where-Object { $_.Name -notin @('.git', 'aws-infra', 'logops-deploy.zip') -and $_.Name -notlike 'terraform.tfstate*' }
) -DestinationPath $zipPath -Force
# Also include aws-infra tf files without state
Compress-Archive -Path (Join-Path $TfDir '*.tf'), (Join-Path $TfDir 'terraform.tfvars.example') -DestinationPath $zipPath -Update

$sshUser = if ($env:EC2_SSH_USER) { $env:EC2_SSH_USER } else { "ec2-user" }

Write-Host ""
Write-Host "===== NEXT COMMANDS (Git Bash or WSL recommended) =====" -ForegroundColor Cyan
Write-Host "scp -i `"$keyPath`" `"$zipPath`" ${sshUser}@${ec2Ip}:/home/${sshUser}/logops-deploy.zip"
Write-Host "ssh -i `"$keyPath`" ${sshUser}@${ec2Ip}"
Write-Host @"
# then on EC2:
sudo bash /opt/logops/scripts/setup-aws-linux.sh 2>/dev/null || true
sudo mkdir -p /opt/logops && sudo chown ${sshUser}:${sshUser} /opt/logops
cd /opt/logops
unzip -o ~/logops-deploy.zip -d /opt/logops
cp -n .env.example .env || true
# paste MSK/S3 from your laptop .env, then:
export AIRFLOW_UID=`$(id -u)
docker compose up -d --build
bash scripts/health-check.sh
"@
Write-Host "UIs:" -ForegroundColor Cyan
Write-Host "  Airflow  http://$ec2Ip`:8080"
Write-Host "  Grafana  http://$ec2Ip`:3000"
Write-Host "  Superset http://$ec2Ip`:8088"
Write-Host "  Kafka UI http://$ec2Ip`:8081"
