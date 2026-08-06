#!/usr/bin/env bash
# =============================================================================
# LogOps — Generate beginner-safe secrets into .env
# Creates .env from .env.example (if needed) and fills random passwords + Fernet.
# Does NOT overwrite AWS/Databricks placeholders you still need to paste manually.
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
EXAMPLE_FILE="${ROOT_DIR}/.env.example"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

rand_password() {
  # 24-char URL-safe-ish password from /dev/urandom
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -d '/+=' | cut -c1-24
  else
    head -c 32 /dev/urandom | base64 | tr -d '/+=' | cut -c1-24
  fi
}

generate_fernet() {
  # Airflow Fernet key must be url-safe base64-encoded 32-byte key
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
PY
    return
  fi
  # Fallback without cryptography package: openssl 32 bytes -> urlsafe base64
  openssl rand -base64 32 | tr '+/' '-_'
}

upsert_env() {
  # Set KEY=VALUE in .env whether the key exists or not
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    # Portable-ish in-place replace using a temp file
    local tmp
    tmp="$(mktemp)"
    awk -v k="${key}" -v v="${value}" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v} {print}' "${ENV_FILE}" >"${tmp}"
    mv "${tmp}" "${ENV_FILE}"
  else
    echo "${key}=${value}" >>"${ENV_FILE}"
  fi
}

main() {
  if [[ ! -f "${EXAMPLE_FILE}" ]]; then
    echo "Missing ${EXAMPLE_FILE}" >&2
    exit 1
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${EXAMPLE_FILE}" "${ENV_FILE}"
    log "Created ${ENV_FILE} from example"
  else
    log "Updating existing ${ENV_FILE}"
  fi

  # Try generating a real Fernet key; if cryptography is missing, install tip
  local fernet
  if fernet="$(generate_fernet 2>/dev/null)" && [[ -n "${fernet}" ]]; then
    upsert_env "AIRFLOW_FERNET_KEY" "${fernet}"
  else
    log "Install cryptography for a perfect Fernet key: pip install cryptography"
    upsert_env "AIRFLOW_FERNET_KEY" "$(openssl rand -base64 32 | tr '+/' '-_')"
  fi

  upsert_env "AIRFLOW_POSTGRES_PASSWORD" "$(rand_password)"
  upsert_env "AIRFLOW_ADMIN_PASSWORD" "$(rand_password)"
  upsert_env "CLICKHOUSE_PASSWORD" "$(rand_password)"
  upsert_env "MINIO_ROOT_USER" "logopsminio"
  upsert_env "MINIO_ROOT_PASSWORD" "$(rand_password)"
  upsert_env "GRAFANA_ADMIN_PASSWORD" "$(rand_password)"
  upsert_env "SUPERSET_SECRET_KEY" "$(rand_password)$(rand_password)"
  upsert_env "SUPERSET_ADMIN_PASSWORD" "$(rand_password)"

  log "Random secrets written."
  log "Still fill manually: AWS region, MSK brokers, S3 bucket, Databricks host/token/job IDs, SSH key, email/SMTP, Slack."
  log "Open ${ENV_FILE} and search for [FILL_IN_YOUR_"
}

main "$@"
