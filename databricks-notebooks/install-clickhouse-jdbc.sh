#!/bin/bash
# ClickHouse JDBC jar installer for Databricks Gold job clusters.
# Attach as a cluster init script in the Databricks UI.
set -euo pipefail

# Download ClickHouse JDBC driver into the cluster's extra jars folder
JAR_DIR="/databricks/jars"
mkdir -p "${JAR_DIR}"
curl -fsSL \
  "https://repo1.maven.org/maven2/com/clickhouse/clickhouse-jdbc/0.6.0/clickhouse-jdbc-0.6.0-all.jar" \
  -o "${JAR_DIR}/clickhouse-jdbc-0.6.0-all.jar"

echo "ClickHouse JDBC driver installed"
