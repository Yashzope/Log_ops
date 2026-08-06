#!/usr/bin/env bash
# =============================================================================
# LogOps — One-command local demo (Linux / macOS / Git Bash / WSL)
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  if [[ -f .env.local.example ]]; then
    cp .env.local.example .env
    log "Created .env from .env.local.example"
  else
    cp .env.example .env
    log "Created .env from .env.example"
  fi
fi

# Force local Kafka bootstrap
tmp="$(mktemp)"
awk 'BEGIN{FS=OFS="="} $1=="MSK_BOOTSTRAP_SERVERS"{$2="kafka:29092"} {print}' .env >"${tmp}"
mv "${tmp}" .env

if grep -Eq 'FILL_IN_YOUR_|will_be_replaced|change_me' .env; then
  log "Refreshing secrets..."
  bash scripts/generate-secrets.sh || true
  tmp="$(mktemp)"
  awk 'BEGIN{FS=OFS="="} $1=="MSK_BOOTSTRAP_SERVERS"{$2="kafka:29092"} {print}' .env >"${tmp}"
  mv "${tmp}" .env
fi

export AIRFLOW_UID="${AIRFLOW_UID:-$(id -u)}"

log "Starting compose + local Kafka..."
docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml up -d --build

log "Waiting 25s..."
sleep 25
docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml ps

GRAFANA_PASS="$(grep -E '^GRAFANA_ADMIN_PASSWORD=' .env | cut -d= -f2- || true)"
AIRFLOW_PASS="$(grep -E '^AIRFLOW_ADMIN_PASSWORD=' .env | cut -d= -f2- || true)"

cat <<EOF

===== LogOps local demo =====
Grafana : http://localhost:3000   (admin / ${GRAFANA_PASS})
Airflow : http://localhost:8080   (admin / ${AIRFLOW_PASS})
Kafka UI: http://localhost:8081
ClickHouse: http://localhost:8123

Stop with:
  docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml down
EOF
