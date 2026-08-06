# LogOps — Beginner Walkthrough

This guide assumes you are new to these tools.  
For every piece it answers: **what it is**, **why we use it**, **where to click**, **which option to pick**, and **where to paste the value**.

---

## Big picture (one story)

Imagine logs are packages on a conveyor belt:

```text
App logs  -->  Fluent Bit (packer)  -->  Kafka (conveyor)  -->  Processor / Databricks (factory)
                                                              |
                                                              v
                                                         ClickHouse (warehouse)
                                                              |
                                                              v
                                                          Grafana (TV screen)
```

| Piece | Plain English | Role in LogOps |
|-------|---------------|----------------|
| **Docker** | Runs many apps in boxes on your laptop | Starts Kafka, Airflow, Grafana, etc. |
| **Fluent Bit** | Small log collector | Reads log files and sends them to Kafka |
| **Kafka** | Message queue / conveyor | Holds raw logs until something reads them |
| **ClickHouse** | Fast analytics database | Stores metrics for dashboards |
| **Grafana** | Charts / dashboards | You *look* at the data here |
| **Airflow** | Job scheduler / manager | Starts Databricks jobs on a schedule |
| **Databricks** | Cloud Spark factory | Cleans and aggregates logs (Bronze/Silver/Gold) |
| **dbt** | SQL transform tool | Builds daily tables inside Databricks |
| **Terraform** | Infra-as-code | Creates AWS VPC, EC2, S3 with code |
| **S3** | Cloud file storage | Stores Delta Lake tables |
| **Slack webhook** | Chat notification URL | Airflow posts “job failed” messages |

**Two modes in this project**

1. **Lite / local demo** — laptop only: Kafka → processor → ClickHouse → Grafana. **No Databricks needed.**  
2. **Full path** — Airflow + Databricks + dbt. **Needs credentials below.**

You already did a lot of (1). Remaining work is mostly (2).

---

## Files where credentials live (bookmark this)

| File | Path | Purpose |
|------|------|---------|
| Main secrets | `C:\Users\91741\Downloads\logops\.env` | Airflow, Databricks, Slack, EC2, passwords |
| dbt login | `C:\Users\91741\Downloads\logops\dbt\logops\profiles.yml` | How dbt connects to Databricks SQL |
| AWS infra | `C:\Users\91741\Downloads\logops\aws-infra\terraform.tfvars` | Region, EC2 size, SSH IP, MSK on/off |
| Airflow connection example | `airflow\config\connections-example.json` | Template for Airflow UI connection |

Open `.env` with Notepad or Cursor. Never commit it to Git with real tokens.

---

# Part A — Technologies you already used

## A1. Docker Desktop

**Why:** Almost every service in LogOps runs as a container. Without Docker, nothing starts.

**Where to go**

1. Start menu → **Docker Desktop**
2. Wait until it says **Engine running** (whale icon steady)

**Then in PowerShell**

```powershell
cd C:\Users\91741\Downloads\logops
.\scripts\Start-Local.ps1
```

**Where you “fill credentials”:** nowhere in Docker UI — passwords are already in `.env`.

---

## A2. Grafana (see the data)

**Why:** Proof the pipeline works. If charts move, logs are flowing.

**Where to go:** http://localhost:3000  

**Options / login**

- User: `admin`
- Password: open `.env` → line `GRAFANA_ADMIN_PASSWORD=...`

**Path inside Grafana:** left menu → **Dashboards** → **LogOps Overview**

---

## A3. Airflow (schedule jobs)

**Why:** Instead of clicking “Run” in Databricks by hand every day, Airflow triggers Bronze / Silver / Gold on a schedule, with retries and Slack alerts.

**Where to go:** http://localhost:8080  

**Login**

- User: `admin` (from `AIRFLOW_ADMIN_USER`)
- Password: `.env` → `AIRFLOW_ADMIN_PASSWORD`

**Important for beginners:** keep DAGs **paused** until Databricks jobs are real. Unpausing too early = red failures.

---

# Part B — Databricks (the cloud factory)

## What is Databricks?

A cloud workspace where Spark jobs run. In LogOps:

| Layer | Name | What it does |
|-------|------|--------------|
| Raw | **Bronze** | Save Kafka logs almost as-is into Delta tables on S3 |
| Clean | **Silver** | Validate / clean data (DLT pipeline) |
| Metrics | **Gold** | 5-minute SLI aggregates → also can feed ClickHouse |

Notebooks live in the repo at:

`C:\Users\91741\Downloads\logops\databricks-notebooks\`

- `01_bronze_streaming.py`
- `02_silver_dlt.py`
- `03_gold_aggregations.py`

---

## B1. Workspace URL (`DATABRICKS_HOST`)

**Why:** Every tool needs to know *which* Databricks cloud to talk to.

**Where to go**

1. Open your Databricks workspace in the browser  
2. Copy only the base URL from the address bar  

Example shapes:

- `https://adb-xxxxxxxxxxxx.azuredatabricks.net`
- `https://dbc-xxxx.cloud.databricks.com`

**Where to fill**

| Place | Field | Exact format |
|-------|--------|--------------|
| `.env` | `DATABRICKS_HOST=` | **with** `https://` |
| `dbt/.../profiles.yml` | `host:` | **without** `https://` |

Example:

```env
DATABRICKS_HOST=https://adb-123.4.azuredatabricks.net
```

```yaml
host: adb-123.4.azuredatabricks.net
```

---

## B2. Personal Access Token (`DATABRICKS_TOKEN`)

**Why:** Password for APIs (Airflow, dbt, CLI). Prefer token over your real login password.

**Where to go (click path)**

1. Databricks → top-right **your user icon**
2. **Settings**
3. Left: **Developer**
4. **Access tokens** → **Manage** → **Generate new token**

**Which options to select**

| Screen choice | What to pick for LogOps |
|---------------|-------------------------|
| Comment / name | `logops` |
| Lifetime | 30–90 days for learning |
| Scope type | **Other APIs** (not only BI Tools) |
| If asked for scopes | include at least: SQL, Jobs/Workflows, Workspace, Unity Catalog |

**BI Tools** alone = Tableau/Power BI / SQL only → **not enough** for Airflow job triggers.

**Where to fill**

| Place | Field |
|-------|--------|
| `.env` | `DATABRICKS_TOKEN=dapi...` |
| `dbt/.../profiles.yml` | `token: dapi...` |
| Airflow UI connection | Password field (see B6) |

---

## B3. SQL Warehouse + HTTP path (needed for **dbt**)

**Why:** dbt does not start Spark clusters. It talks to a **SQL Warehouse** like a database.

**Where to go**

1. Databricks left sidebar → **SQL**
2. **SQL warehouses**
3. Open your warehouse (or **Create SQL warehouse**)

**Which options when creating (beginner defaults)**

| Setting | Suggested choice |
|---------|------------------|
| Name | `logops-sql` |
| Cluster size | **2X-Small** (cheapest for learning) |
| Auto stop | **10–30 minutes** (saves money) |
| Type | Serverless if available, else Classic |

4. Open the warehouse → **Connection details**

You will see something like:

| Label in UI | Example | Goes where |
|-------------|---------|------------|
| Server hostname | `adb-....azuredatabricks.net` | dbt `host` |
| HTTP path | `/sql/1.0/warehouses/760cd816d17f2125` | dbt `http_path` |
| (ID at end of path) | `760cd816d17f2125` | `.env` → `DATABRICKS_SQL_WAREHOUSE_ID` |

**Where to fill — file you have open now**

File: `dbt\logops\profiles.yml`

```yaml
host: adb-xxxx.azuredatabricks.net          # NO https://
token: dapi....                             # same as .env
http_path: /sql/1.0/warehouses/YOUR_ID      # NO square brackets
```

**Common beginner mistake**

Wrong:

```yaml
http_path: [/sql/1.0/warehouses/abc]
```

Right:

```yaml
http_path: /sql/1.0/warehouses/abc
```

---

## B4. Job IDs (Bronze / Silver / Gold) — IMPORTANT

**Why:** Airflow needs a number that means “run *this* Databricks Job”.

**Wrong value (what often gets pasted by mistake)**

```text
/sql/1.0/warehouses/760cd816d17f2125
```

That is an **HTTP path**, not a job ID.

**Right value shape**

```text
123456789012345
```

(digits only — from the Job page URL)

**Where to go to create jobs**

1. Import notebooks first:
   - Left sidebar → **Workspace**
   - Create folder `logops`
   - Menu → **Import** → upload each file from `databricks-notebooks\`
2. Create jobs:
   - Left sidebar → **Workflows** → **Jobs** → **Create job**
3. For each job:

| Job name | Notebook to attach | Then copy |
|----------|--------------------|-----------|
| `logops-bronze` | `01_bronze_streaming` | Job ID into `DATABRICKS_JOB_BRONZE_ID` |
| `logops-silver` | DLT pipeline from `02_silver_dlt` | Pipeline/job ID into `DATABRICKS_JOB_SILVER_DLT_ID` |
| `logops-gold` | `03_gold_aggregations` | Job ID into `DATABRICKS_JOB_GOLD_ID` |

**Silver is special:** `02_silver_dlt.py` is meant as a **Delta Live Tables** pipeline:

1. **Workflows** → **Delta Live Tables** (or **Pipelines**)
2. **Create pipeline**
3. Select the silver notebook
4. Copy the **pipeline ID**

**Where to fill**

`.env`:

```env
DATABRICKS_JOB_BRONZE_ID=111111111111111
DATABRICKS_JOB_SILVER_DLT_ID=222222222222222
DATABRICKS_JOB_GOLD_ID=333333333333333
```

---

## B5. Cluster ID (optional)

**Why:** Some notebooks can run on a fixed “all-purpose” cluster instead of a job cluster.

**Where:** **Compute** → click your cluster → copy **Cluster ID** from details/URL.

**Where to fill:** `.env` → `DATABRICKS_EXISTING_CLUSTER_ID=`  

Leave empty if you only use Jobs with new clusters.

---

## B6. Airflow connection `databricks_default`

**Why:** DAGs call Databricks through this named connection.

**Where to go**

1. http://localhost:8080
2. **Admin** → **Connections**
3. **+** (Add)

**Which options / fields**

| Field | What to type |
|-------|----------------|
| Connection Id | `databricks_default` exactly |
| Connection Type | `Databricks` |
| Host | same as `DATABRICKS_HOST` |
| Login | `token` |
| Password | your `DATABRICKS_TOKEN` |

Save → then unpause DAGs only after job IDs are correct.

---

# Part C — dbt (SQL transforms)

## What is dbt?

You write SQL models; dbt runs them in order against Databricks and builds clean tables (e.g. daily metrics).

**Project path:** `C:\Users\91741\Downloads\logops\dbt\logops\`

**Credentials file:** `profiles.yml` (this is separate from `.env` on purpose — dbt reads `profiles.yml`).

**After filling profiles.yml**

```powershell
cd C:\Users\91741\Downloads\logops\dbt\logops
dbt debug
dbt run
```

- `dbt debug` = “can I connect?”  
- `dbt run` = “build the models”

If `dbt` command is missing, install later with pip — ask when you reach this step.

---

# Part D — Slack & email alerts

## Slack webhook (optional but useful)

**Why:** When an Airflow task fails, you get a message in Slack instead of only looking at the Airflow UI.

**Where to go:** https://api.slack.com/apps → Create app → **Incoming Webhooks** → On → Add to channel → copy URL

**Where to fill:** `.env` → `SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...`

## SMTP email (optional)

**Why:** Same idea, but email.

**Where to fill in `.env`**

```env
AIRFLOW_SMTP_HOST=smtp.gmail.com
AIRFLOW_SMTP_USER=you@gmail.com
AIRFLOW_SMTP_PASSWORD=app-password-not-normal-password
AIRFLOW_SMTP_MAIL_FROM=you@gmail.com
ALERT_EMAIL=you@gmail.com
```

Skip this if Slack is enough.

---

# Part E — AWS pieces (already mostly done)

| Thing | Why | Where credentials live |
|-------|-----|------------------------|
| AWS CLI keys | Let Terraform create cloud resources | Already on your PC via `aws configure` |
| Terraform | Creates VPC, EC2, S3 | `aws-infra\terraform.tfvars` |
| EC2 | Cheap Linux server in cloud | IP in `.env` → `EC2_PUBLIC_IP` |
| PEM key | SSH into EC2 | `EC2_SSH_KEY_PATH` in `.env` |
| S3 bucket | Stores Delta data files | `.env` → `S3_BUCKET` (must match Terraform) |
| MSK | Managed Kafka on AWS | Currently **off** (`enable_msk = false`) to save money |

You do **not** need to re-enter AWS keys for the next Databricks/dbt steps.

---

# Part F — Exact order to finish (beginner path)

Do these in order. Do not skip ahead.

### Step 1 — Fix `profiles.yml` (you are here)

Open: `dbt\logops\profiles.yml`

1. Copy host from `.env` `DATABRICKS_HOST` → remove `https://` → paste as `host:`
2. Copy `DATABRICKS_TOKEN` → paste as `token:`
3. Set `http_path:` to `/sql/1.0/warehouses/<your-id>` **without brackets**

### Step 2 — Fix job IDs in `.env`

Replace any `/sql/1.0/warehouses/...` values under `DATABRICKS_JOB_*` with real numeric Job / Pipeline IDs from Databricks **Workflows**.

### Step 3 — Import notebooks + create Jobs/DLT

Use Part B4 click paths.

### Step 4 — Start Docker + Airflow

```powershell
# Start Docker Desktop first, wait until Engine running
cd C:\Users\91741\Downloads\logops
.\scripts\Start-Local.ps1
```

### Step 5 — Add Airflow connection

Part B6 → `databricks_default`

### Step 6 — Unpause one DAG and test

Start with Gold or Bronze only. Watch Airflow graph turn green/red. Check Slack if configured.

### Step 7 — Run dbt

```powershell
cd C:\Users\91741\Downloads\logops\dbt\logops
dbt debug
dbt run
```

---

# Quick “where do I paste this?” cheat sheet

| I copied this from the UI… | Paste it here |
|----------------------------|---------------|
| Browser URL of workspace | `.env` `DATABRICKS_HOST` + dbt `host` (no https) |
| Token starting with `dapi` | `.env` `DATABRICKS_TOKEN` + dbt `token` + Airflow connection password |
| SQL warehouse **HTTP path** | dbt `http_path` only |
| SQL warehouse ID | `.env` `DATABRICKS_SQL_WAREHOUSE_ID` |
| Job number from Workflows URL | `.env` `DATABRICKS_JOB_BRONZE_ID` / `_SILVER_` / `_GOLD_` |
| Slack webhook URL | `.env` `SLACK_WEBHOOK_URL` |
| Cluster ID | `.env` `DATABRICKS_EXISTING_CLUSTER_ID` (optional) |

---

# What you can ignore for now

- MSK (AWS Kafka) — optional / costs money  
- SMTP email — optional if Slack works  
- Prometheus monitoring compose — optional  
- Superset — optional; Grafana is enough for demos  

---

If you tell me which step you are on (1–7), the next message can be only that step’s clicks, with screenshots-style “click here → then here” detail and nothing else.
