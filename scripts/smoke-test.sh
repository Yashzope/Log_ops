#!/usr/bin/env bash
# =============================================================================
# LogOps — End-to-end smoke test (run on the Docker host after compose is up)
# Checks generator → log files → Fluent Bit → ClickHouse schema readiness.
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

# Load .env if present
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

log "1/4 Running container health-check..."
bash scripts/health-check.sh

log "2/4 Checking log-generator output inside the shared volume..."
if docker exec logops-log-generator test -s /var/log/logops/app_logs.json; then
  echo "  PASS — app_logs.json has data"
else
  echo "  FAIL — app_logs.json missing/empty" >&2
  exit 1
fi

log "3/4 Checking Fluent Bit is shipping (look for recent container logs)..."
if docker logs logops-fluent-bit 2>&1 | tail -n 50 | grep -Eqi 'stdout|kafka|app.logs|nginx'; then
  echo "  PASS — Fluent Bit produced recent activity"
else
  echo "  WARN — could not confirm Fluent Bit output; check: docker logs logops-fluent-bit"
fi

log "4/4 Verifying ClickHouse tables exist..."
CH_USER="${CLICKHOUSE_USER:-logops}"
CH_PASS="${CLICKHOUSE_PASSWORD:-}"
tables="$(curl -fsS "http://localhost:8123/" --user "${CH_USER}:${CH_PASS}" \
  --data-binary "SHOW TABLES FROM logops" || true)"
echo "${tables}" | grep -q "raw_logs" || { echo "  FAIL — raw_logs missing"; exit 1; }
echo "${tables}" | grep -q "metrics_5min" || { echo "  FAIL — metrics_5min missing"; exit 1; }
echo "  PASS — tables present:"
echo "${tables}" | sed 's/^/    /'

log "Smoke test complete. Next: unpause Airflow DAGs and import Databricks notebooks."
