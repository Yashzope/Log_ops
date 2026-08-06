# LogOps — Problem Statement

## Title

**LogOps — Centralized Real-Time Log Analytics Platform**

---

## The Real-World Problem

Modern applications (banking apps, e-commerce websites, hospital systems, stock trading platforms) generate billions of log lines per day. These logs are like the application's heartbeat — they record:

- Who logged in and from where
- Which API failed and why
- How slow a payment page was
- When a server ran out of memory

But here is what actually happens in most companies:

| Problem | What It Means in Simple Terms |
| -------- | ----------------------------- |
| Logs are everywhere | App logs sit on Server A, database logs on Server B, web server logs on Server C. No single place to look. |
| Too much, too fast | A single app can write 50,000 lines per second. Humans cannot read that. Spreadsheets crash. |
| Slow means blind | If you can only analyze yesterday's logs today, you find out about a crash after customers have already left. |
| Bad data sneaks in | Sometimes logs are corrupted, timestamps are wrong, or status codes are missing. If you build reports on garbage data, you make garbage decisions. |
| Storage is expensive | Keeping 3 years of logs in a fast database costs lakhs per month. But you cannot just delete them — compliance rules (RBI, SEBI, HIPAA) require you to keep them for years. |

**The result:** When a payment fails on a Friday night, the engineering team spends 4 hours collecting files from 20 servers. By Monday morning, the company has lost customer trust and revenue.

---

## What LogOps Solves

LogOps is a centralized log analytics platform that acts like a super-efficient hospital records department for software systems.

Instead of nurses running between wards with paper files, LogOps does four things automatically:

### 1. Collects Everything in Real Time

A lightweight agent called **Fluent Bit** sits on every server like a digital security guard. It watches log files the moment they are written and instantly ships them to a message queue (**Kafka**). Nothing is lost. Nothing is delayed.

> **Analogy:** Instead of collecting patient files at the end of the day, the nurse scans every prescription the second the doctor writes it.

### 2. Processes and Cleans Data Automatically

Raw logs are messy. They come in different formats (JSON, plain text, CSV). Some are missing fields. Some have wrong timestamps.

**Databricks** (running Apache Spark) reads these logs from Kafka, parses them, validates them, and sorts them into three clean layers:

| Layer | Name | What It Holds |
| ----- | ---- | ------------- |
| Bronze | Raw | Exactly what arrived — untouched, for audit |
| Silver | Cleaned | Validated, deduplicated, enriched with extra info (like "is this an error?") |
| Gold | Business-ready | Pre-calculated metrics like "average response time per service every 5 minutes" |

**Delta Live Tables** automatically reject bad records (like a bouncer at a club) and quarantine them for inspection.

> **Analogy:** The hospital's data entry team checks every scanned prescription for spelling errors, wrong dates, and missing patient IDs before filing it.

### 3. Serves Data at Two (Three) Speeds

Not all data needs the same treatment:

| Tier | Window | Store | Purpose |
| ---- | ------ | ----- | ------- |
| **Hot** | Last 7 days | ClickHouse | Grafana dashboards — "Is the website down right now?" |
| **Warm** | Last 30 days | Delta Lake on S3 | Analyst questions — "Which API was slowest last Tuesday?" |
| **Cold** | 1+ years | S3 Glacier | Compliance / audit — cheap long-term retention |

> **Analogy:** Current patients' files sit on the doctor's desk. Last month's files are in the filing cabinet down the hall. Old records from 2020 are in a warehouse basement — accessible if needed, but not taking up expensive desk space.

### 4. Orchestrates Everything Reliably

**Apache Airflow** is the project manager. It wakes up on schedule, tells Databricks to compact files, runs data quality checks, archives old data, and emails / Slack-notifies the team if anything fails. If a job crashes at 2 AM, Airflow retries it automatically instead of waking up an engineer.

---

## Outcome

One place to see “is the system healthy right now?”, investigate recent incidents from curated data, and retain older logs cheaply for audit — instead of a multi-hour scavenger hunt across servers.

---

## Interview One-Liner

> LogOps turns scattered, high-volume application logs into a real-time, quality-checked, tiered analytics pipeline so teams detect failures in minutes, not Monday morning.

---

## How This Maps to the Repo

| Pillar | Components |
| ------ | ---------- |
| Collect | `log-generator/`, `fluent-bit/`, Kafka (local or MSK) |
| Process | `databricks-notebooks/` Bronze → Silver DLT → Gold |
| Serve | `clickhouse/` + `grafana/` (hot), Delta on S3 (warm), Glacier lifecycle (cold) |
| Orchestrate | `airflow/dags/`, Terraform in `aws-infra/` |

See also:

- [DATASETS.md](./DATASETS.md) — **NASA-HTTP chosen**; download + replay instructions
- [BEGINNER_WALKTHROUGH.md](./BEGINNER_WALKTHROUGH.md)
- [REMAINING_CREDENTIALS.md](./REMAINING_CREDENTIALS.md)
