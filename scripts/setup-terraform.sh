#!/usr/bin/env bash
# =============================================================================
# LogOps — Terraform init / validate / plan helper
# Run from your laptop (with AWS credentials configured).
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/aws-infra"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

require_cmd() {
  # Fail early if a required CLI is missing
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_tfvars() {
  # Copy the example tfvars once so beginners have a file to edit
  if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
    log "Creating terraform.tfvars from example — fill in [FILL_IN_YOUR_XXX] values"
    cp "${TF_DIR}/terraform.tfvars.example" "${TF_DIR}/terraform.tfvars"
    echo "Edit ${TF_DIR}/terraform.tfvars before applying." >&2
    exit 1
  fi
}

main() {
  require_cmd terraform
  require_cmd aws
  ensure_tfvars

  cd "${TF_DIR}"

  log "Initializing Terraform (local backend)..."
  terraform init -input=false

  log "Validating Terraform configuration..."
  terraform validate

  log "Formatting Terraform files..."
  terraform fmt -recursive

  log "Creating plan (saved to tfplan)..."
  terraform plan -input=false -out=tfplan

  log "Done. Review the plan, then run: cd aws-infra && terraform apply tfplan"
}

main "$@"
