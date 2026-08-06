# =============================================================================
# LogOps — Interview cheat-sheet (print this before a call)
#
#   .\scripts\Show-Interview-Talking-Points.ps1
# =============================================================================

Write-Host ""
Write-Host "===== LogOps - what to tell interviewers =====" -ForegroundColor Cyan
Write-Host @'

Problem
  Observability for microservices: collect logs, enrich them, analyze SLIs.

Architecture (medallion)
  Bronze  : raw Kafka events -> Delta/raw store
  Silver  : cleaned/validated logs (DLT expectations)
  Gold    : 5-minute metrics (requests, errors, p95) -> ClickHouse + Grafana

Components I can defend
  Fluent Bit   : tail logs, JSON/nginx parsers, Lua geo enrichment, Kafka output
  Kafka/MSK    : durable buffer between producers and processors
  Spark/DLT    : streaming parse + data quality expectations (Databricks notebooks)
  Airflow      : schedule Bronze/Silver/Gold/VACUUM with retries, SLA, Slack/email
  ClickHouse   : OLAP store for dashboards (TTL on raw vs metrics)
  Grafana      : requests/sec, error %, p95, top services
  Terraform    : VPC, EC2, S3, IAM, optional MSK
  dbt          : daily marts on curated tables

Tradeoffs I made
  Local/demo uses a Python Kafka->ClickHouse processor instead of Databricks Gold
  Free Tier account: t3.small + MSK disabled; lite compose instead of full Airflow on EC2
  Campus network blocked UI ports -> SSH tunnel for Grafana/Kafka UI

Failure modes I handled
  Retries on ClickHouse writes, Compose healthchecks, graceful log-generator shutdown
  Terraform enable_msk flag when account lacks MSK subscription
  Fernet/secrets generator so beginners do not hand-write keys

Next production hardening
  MSK IAM/TLS, private subnets, no 0.0.0.0/0 UI ports, Secrets Manager,
  Unity Catalog governance, alerting on error_rate SLO burn

'@
