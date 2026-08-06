# =============================================================================
# LogOps — Tear down AWS resources (stops EC2/S3/VPC billing)
# WARNING: destroys cloud infra created by Terraform.
#
#   .\scripts\Stop-Aws.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $RootDir "aws-infra"

Write-Host "This will DESTROY LogOps AWS resources (EC2, VPC, S3 bucket data, etc.)." -ForegroundColor Yellow
$confirm = Read-Host "Type destroy to continue"
if ($confirm -ne "destroy") {
    Write-Host "Aborted."
    exit 0
}

Set-Location $TfDir
terraform destroy -input=false -auto-approve
Write-Host "AWS resources destroyed. Local Docker demo is unchanged."
