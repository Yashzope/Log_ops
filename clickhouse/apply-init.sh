#!/usr/bin/env bash
# =============================================================================
# LogOps — Apply ClickHouse init.sql with retries
# Used by the clickhouse-init one-shot Compose service.
# =============================================================================

set -euo pipefail

HOST="${CLICKHOUSE_HOST:-clickhouse}"
USER_NAME="${CLICKHOUSE_USER:-logops}"
PASSWORD="${CLICKHOUSE_PASSWORD:-}"
SQL_FILE="${SQL_FILE:-/init.sql}"

echo "[clickhouse-init] Waiting for ClickHouse at ${HOST}:8123 ..."

for attempt in $(seq 1 30); do
  if wget -qO- "http://${HOST}:8123/ping" >/dev/null 2>&1; then
    echo "[clickhouse-init] ClickHouse is up"
    break
  fi
  if [[ "${attempt}" -eq 30 ]]; then
    echo "[clickhouse-init] ERROR: ClickHouse never became ready" >&2
    exit 1
  fi
  sleep 2
done

echo "[clickhouse-init] Applying ${SQL_FILE} via clickhouse-client ..."

# Prefer the native client (handles comments + multi-statements cleanly)
clickhouse-client \
  --host "${HOST}" \
  --user "${USER_NAME}" \
  --password "${PASSWORD}" \
  --multiquery \
  --queries-file "${SQL_FILE}"

echo "[clickhouse-init] Schema applied successfully"
