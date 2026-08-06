#!/bin/bash
set -euo pipefail
USER_NAME="${SUPERSET_ADMIN_USER:-${ADMIN_USERNAME:-admin}}"
USER_PASS="${SUPERSET_ADMIN_PASSWORD:-${ADMIN_PASSWORD:-}}"
USER_EMAIL="${SUPERSET_ADMIN_EMAIL:-${ADMIN_EMAIL:-admin@logops.demo}}"

if [ -z "$USER_PASS" ]; then
  echo "SUPERSET_ADMIN_PASSWORD / ADMIN_PASSWORD is empty" >&2
  exit 1
fi

superset db upgrade
superset fab create-admin \
  --username "$USER_NAME" \
  --firstname Admin \
  --lastname LogOps \
  --email "$USER_EMAIL" \
  --password "$USER_PASS" || true
superset fab reset-password --username "$USER_NAME" --password "$USER_PASS" || true
superset init
echo "SUPERSET_INIT_DONE user=$USER_NAME"
