# =============================================================================
# LogOps — Windows helper: Terraform init / validate / plan
# Prerequisites: Terraform + AWS CLI installed and `aws configure` completed.
# Run:
#   .\scripts\Setup-Terraform.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $RootDir "aws-infra"

function Write-Log($Message) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

foreach ($cmd in @("terraform", "aws")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $cmd"
    }
}

$tfvars = Join-Path $TfDir "terraform.tfvars"
$example = Join-Path $TfDir "terraform.tfvars.example"
if (-not (Test-Path $tfvars)) {
    Copy-Item $example $tfvars
    Write-Log "Created terraform.tfvars — fill every [FILL_IN_YOUR_XXX] then re-run."
    exit 1
}

Set-Location $TfDir
Write-Log "terraform init"
terraform init -input=false

Write-Log "terraform validate"
terraform validate

Write-Log "terraform fmt"
terraform fmt -recursive

Write-Log "terraform plan -> tfplan"
terraform plan -input=false -out=tfplan

Write-Log "Done. Review the plan, then: cd aws-infra; terraform apply tfplan"
