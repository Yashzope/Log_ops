#!/usr/bin/env bash
# =============================================================================
# LogOps — One-command deploy
# 1) terraform apply
# 2) scp project files to EC2
# 3) ssh and docker compose up -d
# Requires .env with EC2_PUBLIC_IP / EC2_SSH_KEY_PATH filled in.
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/aws-infra"
ENV_FILE="${ROOT_DIR}/.env"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

load_env() {
  # Load deploy variables from .env if present
  if [[ ! -f "${ENV_FILE}" ]]; then
    die "Missing ${ENV_FILE}. Copy .env.example to .env and fill placeholders."
  fi
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
}

require_vars() {
  # Ensure critical deploy variables are set and not placeholders
  local var
  for var in EC2_SSH_KEY_PATH EC2_SSH_USER; do
    if [[ -z "${!var:-}" || "${!var}" == \[FILL_IN* ]]; then
      die "Set ${var} in .env before deploying."
    fi
  done
  if [[ ! -f "${EC2_SSH_KEY_PATH}" ]]; then
    die "SSH key not found at ${EC2_SSH_KEY_PATH}"
  fi
  chmod 400 "${EC2_SSH_KEY_PATH}" || true
}

terraform_apply() {
  # Apply infrastructure if a plan exists; otherwise plan+apply
  log "Applying Terraform..."
  cd "${TF_DIR}"
  if [[ ! -f terraform.tfvars ]]; then
    die "Missing aws-infra/terraform.tfvars — copy from terraform.tfvars.example"
  fi
  terraform init -input=false
  if [[ -f tfplan ]]; then
    terraform apply -input=false tfplan
  else
    terraform apply -input=false -auto-approve
  fi

  # Capture outputs for later steps
  EC2_PUBLIC_IP="$(terraform output -raw ec2_public_ip)"
  MSK_BOOTSTRAP_SERVERS="$(terraform output -raw msk_bootstrap_brokers)"
  S3_BUCKET="$(terraform output -raw s3_bucket_name)"
  export EC2_PUBLIC_IP MSK_BOOTSTRAP_SERVERS S3_BUCKET
  log "EC2 IP=${EC2_PUBLIC_IP}"
  log "MSK brokers=${MSK_BOOTSTRAP_SERVERS}"
  log "S3 bucket=${S3_BUCKET}"
}

wait_for_ssh() {
  # Retry SSH until the instance accepts connections
  log "Waiting for SSH on ${EC2_PUBLIC_IP}..."
  local attempt
  for attempt in $(seq 1 30); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      -i "${EC2_SSH_KEY_PATH}" "${EC2_SSH_USER}@${EC2_PUBLIC_IP}" "echo ok" >/dev/null 2>&1; then
      log "SSH is ready"
      return 0
    fi
    sleep 10
  done
  die "SSH never became ready on ${EC2_PUBLIC_IP}"
}

sync_files() {
  # Copy the project tree to /opt/logops on the EC2 host
  log "Syncing project files to EC2..."
  ssh -o StrictHostKeyChecking=no -i "${EC2_SSH_KEY_PATH}" \
    "${EC2_SSH_USER}@${EC2_PUBLIC_IP}" "sudo mkdir -p /opt/logops && sudo chown ${EC2_SSH_USER}:${EC2_SSH_USER} /opt/logops"

  if command -v rsync >/dev/null 2>&1; then
    rsync -az --delete \
      --exclude '.git' \
      --exclude 'aws-infra/terraform.tfstate*' \
      --exclude 'aws-infra/.terraform' \
      -e "ssh -o StrictHostKeyChecking=no -i ${EC2_SSH_KEY_PATH}" \
      "${ROOT_DIR}/" "${EC2_SSH_USER}@${EC2_PUBLIC_IP}:/opt/logops/"
  else
    tar czf - \
      --exclude '.git' \
      --exclude 'aws-infra/.terraform' \
      --exclude 'aws-infra/terraform.tfstate*' \
      -C "${ROOT_DIR}" . \
      | ssh -o StrictHostKeyChecking=no -i "${EC2_SSH_KEY_PATH}" \
        "${EC2_SSH_USER}@${EC2_PUBLIC_IP}" "tar xzf - -C /opt/logops"
  fi
}

remote_compose_up() {
  # On EC2: ensure Docker is installed, write .env, start the stack
  log "Starting Docker Compose on EC2..."
  ssh -o StrictHostKeyChecking=no -i "${EC2_SSH_KEY_PATH}" \
    "${EC2_SSH_USER}@${EC2_PUBLIC_IP}" \
    "MSK_BOOTSTRAP_SERVERS='${MSK_BOOTSTRAP_SERVERS}' S3_BUCKET='${S3_BUCKET}' EC2_PUBLIC_IP='${EC2_PUBLIC_IP}' bash -s" <<'EOF'
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  sudo bash /opt/logops/scripts/setup-aws-linux.sh
fi
cd /opt/logops
if [[ ! -f .env ]]; then
  cp .env.example .env
fi
python3 - <<PY
from pathlib import Path
import os
env_path = Path(".env")
text = env_path.read_text()
replacements = {
    "MSK_BOOTSTRAP_SERVERS=": f"MSK_BOOTSTRAP_SERVERS={os.environ['MSK_BOOTSTRAP_SERVERS']}",
    "S3_BUCKET=": f"S3_BUCKET={os.environ['S3_BUCKET']}",
    "EC2_PUBLIC_IP=": f"EC2_PUBLIC_IP={os.environ['EC2_PUBLIC_IP']}",
}
lines = []
for line in text.splitlines():
    replaced = False
    for prefix, new in replacements.items():
        if line.startswith(prefix):
            lines.append(new)
            replaced = True
            break
    if not replaced:
        lines.append(line)
env_path.write_text("\n".join(lines) + "\n")
PY
export AIRFLOW_UID=$(id -u)
mkdir -p airflow/logs airflow/plugins
docker compose pull || true
docker compose up -d --build
docker compose ps
EOF
}

print_urls() {
  # Show the beginner where to click next
  log "Deploy finished. Open these URLs:"
  echo "  Airflow : http://${EC2_PUBLIC_IP}:8080"
  echo "  Grafana : http://${EC2_PUBLIC_IP}:3000"
  echo "  Superset: http://${EC2_PUBLIC_IP}:8088"
  echo "  Kafka UI: http://${EC2_PUBLIC_IP}:8081"
}

main() {
  load_env
  require_vars
  terraform_apply
  wait_for_ssh
  sync_files
  remote_compose_up
  print_urls
}

main "$@"
