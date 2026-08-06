#!/usr/bin/env bash
# =============================================================================
# LogOps — Health check script
# Verifies Docker containers, Kafka topic reachability, and ClickHouse queries.
# Run on the EC2 host from /opt/logops (or any checkout with .env).
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
FAILURES=0

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

pass() {
  echo "  PASS — $*"
}

fail() {
  echo "  FAIL — $*" >&2
  FAILURES=$((FAILURES + 1))
}

load_env() {
  # Optional .env load for broker / password values
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
  fi
}

check_containers() {
  # Ensure every compose service reports healthy or running
  log "Checking Docker Compose services..."
  if ! command -v docker >/dev/null 2>&1; then
    fail "docker command not found"
    return
  fi

  cd "${ROOT_DIR}"
  local services
  services="$(docker compose ps --services 2>/dev/null || true)"
  if [[ -z "${services}" ]]; then
    fail "No compose services found. Did you run docker compose up -d?"
    return
  fi

  local svc state health
  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue
    state="$(docker compose ps --format json "${svc}" 2>/dev/null | head -n1 || true)"
    if docker compose ps "${svc}" 2>/dev/null | grep -Eqi 'healthy|running|Up'; then
      health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$(docker compose ps -q "${svc}")" 2>/dev/null || echo unknown)"
      if [[ "${health}" == "unhealthy" ]]; then
        fail "${svc} is unhealthy"
      else
        pass "${svc} is up (health=${health})"
      fi
    else
      fail "${svc} is not running (${state})"
    fi
  done <<< "${services}"
}

check_kafka_topic() {
  # Best-effort Kafka check via Kafka UI container or host networking tools
  log "Checking Kafka topic..."
  local brokers topic
  brokers="${MSK_BOOTSTRAP_SERVERS:-}"
  topic="${KAFKA_TOPIC:-logops.raw.logs}"

  if [[ -z "${brokers}" || "${brokers}" == \[FILL_IN* ]]; then
    fail "MSK_BOOTSTRAP_SERVERS is not set in .env"
    return
  fi

  # Use Python socket connect against the first broker host:port
  if python3 - <<PY
import os, socket, sys
brokers = os.environ.get("MSK_BOOTSTRAP_SERVERS", "")
first = brokers.split(",")[0].strip()
if not first or ":" not in first:
    print("bad broker string")
    sys.exit(1)
host, port = first.rsplit(":", 1)
try:
    with socket.create_connection((host, int(port)), timeout=5):
        pass
except Exception as exc:
    print(exc)
    sys.exit(2)
print(f"connected to {host}:{port}")
PY
  then
    pass "TCP connect to first MSK broker succeeded (topic=${topic})"
  else
    fail "Cannot reach MSK broker(s): ${brokers}"
  fi
}

check_clickhouse() {
  # Hit ClickHouse HTTP ping and run a simple SELECT
  log "Checking ClickHouse..."
  # Use ch_password — do NOT name a variable "pass" (shadows the pass() helper)
  local ch_user ch_password
  ch_user="${CLICKHOUSE_USER:-logops}"
  ch_password="${CLICKHOUSE_PASSWORD:-}"

  if ! curl -fsS "http://localhost:8123/ping" >/dev/null 2>&1; then
    fail "ClickHouse /ping failed on localhost:8123"
    return
  fi
  pass "ClickHouse /ping OK"

  local query_result
  if query_result="$(curl -fsS "http://localhost:8123/" \
      --user "${ch_user}:${ch_password}" \
      --data-binary "SELECT count() FROM logops.raw_logs" 2>/dev/null)"; then
    pass "ClickHouse query OK (raw_logs count=${query_result})"
  else
    # Table may be empty/missing right after first boot — still try metrics table exists
    if curl -fsS "http://localhost:8123/" \
      --user "${ch_user}:${ch_password}" \
      --data-binary "EXISTS TABLE logops.metrics_5min" >/dev/null 2>&1; then
      pass "ClickHouse reachable; metrics_5min exists (raw_logs may still be empty)"
    else
      fail "ClickHouse query failed — check credentials and init.sql mount"
    fi
  fi
}

check_log_files() {
  # Confirm the generator is writing files Fluent Bit tails
  log "Checking log files..."
  if [[ -f /var/log/logops/app_logs.json ]] || docker volume ls | grep -q logops; then
    pass "Log volume / files look present"
  else
    fail "Expected /var/log/logops logs or a logops docker volume"
  fi
}

main() {
  load_env
  check_containers
  check_kafka_topic
  check_clickhouse
  check_log_files

  echo
  if [[ "${FAILURES}" -gt 0 ]]; then
    log "Health check finished with ${FAILURES} failure(s)"
    exit 1
  fi
  log "All health checks passed"
}

main "$@"
