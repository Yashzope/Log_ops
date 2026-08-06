# LogOps — Hot / Warm / Cold Runbook

Beginner map of where log data lives and how long it stays useful.

---

## Hot (last ~7 days) — ClickHouse + Grafana

| What | Where |
| ---- | ----- |
| Store | ClickHouse (`raw_logs`, `metrics_5min`) |
| Retention | ~7 days TTL on raw; metrics may keep longer (e.g. 30d) |
| Use for | Live dashboards, recent error spikes, latency charts |
| UI | Grafana → **LogOps Overview** |

**Mental model:** Hot = “what is broken *right now*?”

---

## Warm (weeks–months) — Delta Silver / Gold + dbt

| What | Where |
| ---- | ----- |
| Clean events | `logops.silver.clean_logs` (DLT) |
| Bad rows | `logops.silver.quarantine_logs` (inspect / fix) |
| Aggregates | `logops.gold.metrics_5min` |
| Marts | dbt models on Silver (`stg_logs`, `fct_daily_metrics`) |
| Use for | Trends, daily rollups, ad-hoc SQL in Databricks |

**Mental model:** Warm = “what happened this month?” — queryable Delta, not yet archived.

---

## Cold (30+ days) — UC archive + S3 Glacier

| What | Where |
| ---- | ----- |
| Free Edition stand-in | `logops.archive.gold_metrics_cold` (Airflow task `mark_cold_archive_candidates`) |
| AWS object cold path | `s3://{S3_BUCKET}/archive/` + Glacier lifecycle rule |
| Trigger | Maintenance DAG inserts gold rows older than **30 days** into the archive schema |
| Use for | Compliance / rare historical pulls, not dashboards |

**Mental model:** Cold = “keep it cheap; dig it up only when auditors ask.”

> Glacier ages objects under the `archive/` prefix in AWS. On Databricks Free Edition, Unity Catalog external S3 writes are often restricted, so the **`logops.archive`** schema is the practical cold tier until you wire an external location.

---

## One-line policy

```
Hot (CH 7d + Grafana) → Warm (Delta silver/gold + dbt) → Cold (logops.archive + s3://…/archive/ Glacier)
```

Nightly Airflow `logops_maintenance` runs OPTIMIZE/VACUUM, then moves old gold into `logops.archive`.
