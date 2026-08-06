# LogOps — Datasets That Align With the Problem Statement

This note picks **real / public log datasets** that match
[PROBLEM_STATEMENT.md](./PROBLEM_STATEMENT.md): scattered web/app logs,
errors, latency, volume, and bad/messy records — not crypto prices or
generic CSVs.

---

## Recommendation (use this)

| Priority | Dataset | Why it fits LogOps | Realtime? |
| -------- | ------- | ------------------ | --------- |
| **1 — CHOSEN** | **NASA-HTTP** | Real public WWW access logs (status, path, host); freely redistributable | Replay as live stream |
| **2 — Live synthetic** | Built-in `log-generator/` | Continuous demo without download | **Yes (live)** |
| **3 — Latency-rich synthetic** | Kaggle Server Logs | Apache + response time | Replay |
| **4 — Multi-service** | AWS sample / LO2v2 | E-commerce / OAuth microservices | Batch / replay |

### How we run NASA-HTTP in this repo

```powershell
.\scripts\Download-Nasa.ps1      # ~20 MB July 1995 gz + 100k-line sample
.\scripts\Start-Lite-Nasa.ps1    # lite stack with nasa-replayer
```

- Dataset folder: `data/nasa/`
- Replayer: `nasa-replayer/replay_nasa.py`
- Compose override: `docker-compose.nasa.yml`

Crypto APIs do **not** align with this problem statement (they are market ticks, not application heartbeats).

---

## Dataset details

### 1) Built-in LogOps generator (already in repo)

- **Path:** `log-generator/generate_logs.py`
- **Outputs:** `app_logs.json` + `nginx_access.log`
- **Aligns to:** “too much, too fast”, API failures, latency, multi-service names (`payments-api`, `auth-service`, …)
- **How to run:** `.\scripts\Start-Lite.ps1`

### 2) NASA-HTTP (real historical web logs)

- **What:** Two months of HTTP requests to NASA Kennedy Space Center WWW server (1995)
- **Format:** Common / combined-style access log lines (host, timestamp, request, status, bytes)
- **Size:** ~3.4M+ requests across the traces; gzip ~20 MB each month
- **Source:** https://ita.ee.lbl.gov/html/contrib/NASA-HTTP.html  
- **Downloads (FTP / mirrors):**  
  - `NASA_access_log_Jul95.gz`  
  - `NASA_access_log_Aug95.gz`
- **Aligns to:** Logs everywhere → centralize; volume; status codes; real-world access patterns (includes a multi-day outage during Hurricane Erin — good “incident” story)
- **Gap vs LogOps Gold:** No explicit `latency_ms` in classic NASA lines — use status/error rate + request volume; or derive synthetic latency when replaying
- **License / use:** Research redistribution allowed by the Internet Traffic Archive terms on that page

**Example line shape:**
```text
199.72.81.55 - - [01/Jul/1995:00:00:01 -0400] "GET /history/apollo/ HTTP/1.0" 200 6245
```

Fluent Bit already has an **nginx** parser — NASA lines are close enough for a beginner pipeline after light normalization.

### 3) Kaggle — Server Logs / Website Log Access (synthetic Apache)

- **What:** Synthetic Apache-style access logs with **status code** and **response time**
- **Why best for Gold metrics:** latency + errors match ClickHouse `metrics_5min` and Grafana panels
- **Links:**  
  - https://www.kaggle.com/datasets/vishnu0399/server-logs  
  - https://www.kaggle.com/datasets/avinhok/website-log-access  
- **License:** Often CC0 / public domain (check the Kaggle page before publishing)
- **Aligns to:** Slow pages, failed APIs, bad/suspicious admin paths, anomaly spikes

### 4) Hugging Face — mindweave/web-server-logs

- **What:** Synthetic SaaS / e-commerce HTTP logs (method, path, status, response time, IP, UA)
- **Bonus:** Injected anomalies (e.g. DDoS / DB outage) — good “Friday night failure” narrative
- **Link:** https://huggingface.co/datasets/mindweave/web-server-logs  
- **Note:** Free sample is small; full set may be commercial — use sample for demos if needed

### 5) Loghub (system / server application logs)

- **What:** Large research collection (Apache error logs, OpenSSH, HDFS, Spark, …)
- **Link:** https://github.com/logpai/loghub  
- **Zenodo:** https://zenodo.org/records/8196385  
- **Aligns to:** “bad/messy formats”, multi-source logs, Silver quality rules  
- **Best subset for LogOps:** **Apache** error log (smaller) first; HDFS/Spark if you want distributed-system scale storytelling  
- **Cite** the Loghub paper if you use it academically

### 6) LO2v2 — microservice logs + metrics (advanced)

- **What:** OAuth2 microservice system logs, metrics, traces
- **Link:** https://zenodo.org/records/18937117  
- **Aligns to:** Multi-service banking/e-commerce style “heartbeat”  
- **Caveat:** Larger / more complex; better as Phase 2 after nginx/JSON path works

### 7) AWS sample webserver logs

- **What:** Synthetic e-commerce web server logs (~10k records)
- **Link:** https://github.com/aws-samples/sample-webserver-logs-dataset  
- **Aligns to:** API paths, status mix, product/browse traffic

---

## How any chosen dataset plugs into LogOps

```text
Public log file  -->  replay script (1 line / N ms)
                         |
                         v
              /var/log/logops/nginx_access.log
              (or app_logs.json for JSON)
                         |
                         v
              Fluent Bit --> Kafka --> processor / Databricks
                         --> ClickHouse --> Grafana
```

**Required fields for full SLI dashboards (error rate + latency):**

| Field | NASA | Kaggle Apache+latency | log-generator |
| ----- | ---- | --------------------- | ------------- |
| timestamp | Yes | Yes | Yes |
| path / message | Yes | Yes | Yes |
| status_code | Yes | Yes | Yes |
| latency_ms | No* | Yes | Yes |
| client_ip | Yes | Yes | Yes |
| service | Map to `nginx` or path prefix | Same | Built-in |

\* For NASA, either focus Gold on volume + error rate, or assign a synthetic latency while replaying.

---

## What we will use going forward

| Mode | Dataset | Purpose |
| ---- | ------- | ------- |
| **Chosen public dataset** | **NASA-HTTP** (`data/nasa/`, `Start-Lite-Nasa.ps1`) | Report + real access-log pipeline |
| **Optional synthetic** | `log-generator` via `Start-Lite.ps1` | Quick demo without download |
| **Not used for this PS** | Crypto APIs, retail CSVs, taxi trips | Wrong domain |

---

## Next steps

1. Run `.\scripts\Download-Nasa.ps1` (already done if `data/nasa/*.gz` exists).  
2. Run `.\scripts\Start-Lite-Nasa.ps1` and open Grafana.  
3. Cite NASA-HTTP + Arlitt & Williamson (SIGMETRICS 1996) in the report.
