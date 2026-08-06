# =============================================================================
# LogOps — Prepare AWS Day-1 files from your logged-in AWS CLI identity
# Creates aws-infra/terraform.tfvars with discovered region / account hints.
# Does NOT run terraform apply (no spend).
#
#   .\scripts\Prepare-Aws.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $RootDir "aws-infra"
$Tfvars = Join-Path $TfDir "terraform.tfvars"
$Example = Join-Path $TfDir "terraform.tfvars.example"

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI not found. Install it, run aws configure, then retry."
}

Write-Log "Checking AWS identity..."
$ident = aws sts get-caller-identity --output json | ConvertFrom-Json
$account = $ident.Account
$arn = $ident.Arn
Write-Host "  Account: $account"
Write-Host "  Arn:     $arn"

$region = aws configure get region
if (-not $region) { $region = "ap-south-1" }
Write-Host "  Region:  $region"

Write-Log "Listing EC2 key pairs in $region..."
$keysJson = aws ec2 describe-key-pairs --region $region --output json | ConvertFrom-Json
$keyNames = @($keysJson.KeyPairs | ForEach-Object { $_.KeyName })
if ($keyNames.Count -eq 0) {
    Write-Host "  No key pairs found." -ForegroundColor Yellow
    Write-Host "  Create one: AWS Console -> EC2 -> Key pairs -> Create key pair"
    Write-Host "  Or CLI:"
    Write-Host "    aws ec2 create-key-pair --region $region --key-name logops-key --query 'KeyMaterial' --output text > `$env:USERPROFILE\logops-key.pem"
    $keyPlaceholder = "[FILL_IN_YOUR_EC2_KEY_PAIR_NAME]"
} else {
    Write-Host "  Found: $($keyNames -join ', ')"
    $keyPlaceholder = $keyNames[0]
    Write-Host "  Using first key by default: $keyPlaceholder (edit terraform.tfvars if wrong)"
}

# Discover public IP for SSH lockdown (best-effort)
$myIp = $null
try {
    $myIp = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
} catch {
    $myIp = $null
}
$sshCidr = if ($myIp) { "$myIp/32" } else { "[FILL_IN_YOUR_SSH_ALLOWED_CIDR]" }
if ($myIp) { Write-Host "  Detected public IP: $myIp" }

$bucket = "logops-delta-$account-$region".ToLower() -replace '_','-'
$owner = ($arn -split '/')[-1]

if (-not (Test-Path $Example)) { throw "Missing $Example" }

if (Test-Path $Tfvars) {
    Write-Log "terraform.tfvars already exists - writing terraform.tfvars.prepared instead"
    $outFile = Join-Path $TfDir "terraform.tfvars.prepared"
} else {
    $outFile = $Tfvars
}

@"
# Auto-prepared by scripts/Prepare-Aws.ps1 - review before terraform apply
aws_region     = "$region"
project_name   = "logops"

ec2_key_pair_name = "$keyPlaceholder"
ssh_allowed_cidr  = "$sshCidr"

# Globally unique bucket suggestion based on your account/region
s3_bucket_name = "$bucket"

ec2_instance_type          = "t3.large"
msk_instance_type          = "kafka.t3.small"
msk_broker_count           = 2
msk_kafka_version          = "3.5.1"
s3_glacier_transition_days = 90
vpc_cidr                   = "10.0.0.0/16"
public_subnet_cidr         = "10.0.1.0/24"
public_subnet_cidr_2       = "10.0.2.0/24"

common_tags = {
  Project     = "LogOps"
  Environment = "dev"
  ManagedBy   = "terraform"
  Owner       = "$owner"
}
"@ | Set-Content -Path $outFile -Encoding UTF8

Write-Log "Wrote $outFile"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
if ($keyNames.Count -eq 0) {
    Write-Host "  1) Create an EC2 key pair and put the name into terraform.tfvars"
}
Write-Host "  2) Install Terraform if needed, then: .\scripts\Setup-Terraform.ps1"
Write-Host "  3) Review the plan carefully (MSK + EC2 cost money)"
Write-Host "  4) Only then apply: cd aws-infra; terraform apply"
Write-Host ""
Write-Host "This script did NOT create any AWS resources."
