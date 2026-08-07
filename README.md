# LogOps — Observability & Log Analytics Platform

Beginner-friendly, production-shaped project that collects logs, streams them through Kafka (AWS MSK), processes them with Databricks (Spark / Delta Live Tables / Delta Lake on S3), orchestrates jobs with Airflow, and visualizes metrics in ClickHouse + Grafana / Superset.

---

## Architecture (ASCII)

```
                    +---------------------------+
                    |   Fake apps / nginx logs  |
                    |   (log-generator)         |
                    +-------------+-------------+
                                  |
                                  v
                    +---------------------------+
                    | Fluent Bit (tail + Lua)   |
                    +-------------+-------------+
                                  |
                                  v
                    +---------------------------+
                    | AWS MSK (Kafka)           |
                    +------+----------+---------+
                           |          |
           Spark Structured|          | (optional local Kafka UI)
           Streaming       v          v
        +----------------------+   +-----------+
        | Databricks Bronze    |   | Kafka UI  |
        | Delta: bronze.raw    |   +-----------+
        +----------+-----------+
                   |
                   v
        +----------------------+
        | Databricks Silver    |
        | DLT expectations     |
        | Delta: silver.clean  |
        +----------+-----------+
                   |
                   v
        +----------------------+     JDBC foreachBatch
        | Databricks Gold      +---------------------> ClickHouse
        | 5-min aggregations   |                       (metrics_5min)
        | Delta on S3          |                            |
        +----------+-----------+                            v
                   |                                  +-----------+
                   v                                  | Grafana   |
             +-----------+                            | Superset  |
             | dbt marts |                            +-----------+
             +-----------+

        Airflow (EC2 + Docker) orchestrates Bronze / Silver / Gold / VACUUM
        Terraform provisions VPC, EC2, MSK, S3, IAM
```
---

## Prerequisites

1. An **AWS account** with permission to create VPC, EC2, MSK, S3, IAM.
2. An **EC2 key pair** already created in your target region (you download the `.pem`).
3. A **Databricks workspace** (AWS) with permission to create jobs, DLT pipelines, and a SQL warehouse.
4. Installed on your laptop: **Terraform >= 1.5**, **AWS CLI**, **Git**, **SSH**, and optionally **rsync**.
5. Enough AWS quota for a `t3.large` and 2× `kafka.t3.small` brokers.

---

## Day 0 — local demo before AWS (recommended)

Prove the pipeline on your laptop with **no AWS account** and **no Databricks**.

### Fastest path (lite stack)

Needs only **Docker Desktop**.

```powershell
cd C:\Users\91741\Downloads\logops
.\scripts\Start-Lite.ps1
```

**With the chosen NASA-HTTP public dataset** (real WWW access logs):

```powershell
.\scripts\Download-Nasa.ps1
.\scripts\Start-Lite-Nasa.ps1
```

See `docs/PROBLEM_STATEMENT.md` and `docs/DATASETS.md`.

This starts:

`log-generator → Fluent Bit → local Kafka → log-processor → ClickHouse → Grafana`

Open **http://localhost:3000** (credentials printed by the script) → Dashboards → **LogOps Overview**.

Or after start:

```powershell
.\scripts\Open-Local.ps1
```

That opens Grafana + Kafka UI and copies the Grafana password to your clipboard.

Verify anytime:

```powershell
.\scripts\Verify-Local.ps1
```

Stop:

```powershell
docker compose -f docker-compose.lite.yml down
```

### EC2 lite stack (after Terraform apply)

If your network blocks ports 3000/8081 (common on campus Wi‑Fi), use an SSH tunnel:

```powershell
.\scripts\Open-Ec2-Tunnel.ps1
```

Then open http://localhost:3000 and http://localhost:8081.

Redeploy the lite stack to EC2 anytime:

```powershell
.\scripts\Deploy-Lite-Ec2.ps1
```

Understand live data / interview prep:

```powershell
.\scripts\Explain-Pipeline.ps1
.\scripts\Show-Interview-Talking-Points.ps1
.\scripts\Status-Ec2.ps1
```

### Full local path (includes Airflow)

```powershell
.\scripts\Start-Local.ps1
```

Airflow DAGs that call Databricks will stay paused / fail until you add real Databricks credentials — that is expected locally.

### What the local processor is

On AWS, **Databricks Gold** writes metrics to ClickHouse.  
On your laptop, `log-processor/` does the same job so Grafana is not empty.

---

## Day 1 — move from laptop demo to AWS (when ready)

Do this only after the local lite demo works and you have an AWS account + key pair.

1. **Prepare tfvars from your AWS CLI session**
   ```powershell
   .\scripts\Prepare-Aws.ps1
   ```
   Creates `aws-infra/terraform.tfvars` with region, suggested S3 bucket, and SSH CIDR.  
   If you have **no EC2 key pair**, create one first (script prints the command).
2. **AWS CLI sanity check**
   ```powershell
   aws sts get-caller-identity
   ```
3. **Plan infrastructure** (Terraform must be installed)
   ```powershell
   .\scripts\Setup-Terraform.ps1
   ```
4. **Apply + get EC2 deploy commands** (costs money — review plan first)
   ```powershell
   .\scripts\Deploy-Windows.ps1
   ```
5. **Databricks** (after EC2 is up): import `databricks-notebooks/*.py`, create jobs/DLT pipeline, paste IDs into `.env`, add Airflow connection `databricks_default`.

Cost reminder: MSK + `t3.large` + Databricks charge continuously — run `terraform destroy` when finished.

---

## Step-by-step deployment (beginner)

### 0) Windows users (PowerShell)

From the project root in PowerShell:

```powershell
# 1) Create .env + random passwords
.\scripts\Generate-Secrets.ps1

# 2) Copy and edit Terraform values
Copy-Item aws-infra\terraform.tfvars.example aws-infra\terraform.tfvars
notepad aws-infra\terraform.tfvars
notepad .env
notepad FILL_IN_CHECKLIST.txt

# 3) Plan infrastructure
.\scripts\Setup-Terraform.ps1

# 4) Apply + print scp/ssh instructions
.\scripts\Deploy-Windows.ps1
```

For a one-shot Linux-style deploy (Git Bash / WSL), use `bash scripts/deploy.sh` instead.

### 1) Unpack / open the project

Open this folder in Cursor or a terminal:

`C:\Users\91741\Downloads\logops` (or your clone path)

### 2) Fill in Terraform variables

```bash
cd aws-infra
cp terraform.tfvars.example terraform.tfvars
```

Replace every `[FILL_IN_YOUR_XXX]` in `terraform.tfvars` (region, key pair name, SSH CIDR, unique S3 bucket name).  
Track progress in `FILL_IN_CHECKLIST.txt`.

### 3) Fill in Docker / app secrets

```bash
# Linux / macOS / Git Bash
bash scripts/generate-secrets.sh

# or manually:
cp .env.example .env
```

Replace every `[FILL_IN_YOUR_XXX]` in `.env` (Databricks host/token, passwords, Slack webhook if you have one).  
You can leave MSK / EC2 IP blank until after Terraform apply — `scripts/deploy.sh` fills those.

### 4) Plan AWS infrastructure

```bash
bash scripts/setup-terraform.sh
```

Review the printed plan carefully (MSK and EC2 cost money).

### 5) Deploy everything

From Git Bash / WSL / Linux:

```bash
bash scripts/deploy.sh
```

This will:

1. `terraform apply`
2. Copy project files to EC2 `/opt/logops`
3. Install Docker if needed
4. `docker compose up -d --build`

### 6) Manual path (if you prefer not to use deploy.sh)

```bash
cd aws-infra && terraform apply
# note outputs: ec2_public_ip, msk_bootstrap_brokers, s3_bucket_name

ssh -i [FILL_IN_YOUR_PEM_FILE].pem ec2-user@[FILL_IN_YOUR_EC2_PUBLIC_IP]
sudo bash /opt/logops/scripts/setup-aws-linux.sh   # after scp'ing the repo
cd /opt/logops
cp .env.example .env   # paste broker URL + secrets
export AIRFLOW_UID=$(id -u)
docker compose up -d --build
```

### 7) Import Databricks notebooks

In Databricks UI → Workspace → create folder `logops` → import:

- `databricks-notebooks/01_bronze_streaming.py`
- `databricks-notebooks/02_silver_dlt.py` (as a **DLT pipeline** notebook)
- `databricks-notebooks/03_gold_aggregations.py`

Create jobs / a DLT pipeline and paste their IDs into `.env`.

### 8) Configure Airflow Databricks connection

Open `http://[EC2_IP]:8080` → Admin → Connections → add `databricks_default` with your host + token.  
Unpause the `logops_*` DAGs.

### 9) Health check

On EC2:

```bash
bash /opt/logops/scripts/health-check.sh
```

### 10) Open UIs

| UI | URL |
|----|-----|
| Airflow | `http://[EC2_IP]:8080` |
| Grafana | `http://[EC2_IP]:3000` |
| Superset | `http://[EC2_IP]:8088` |
| Kafka UI | `http://[EC2_IP]:8081` |

Optional monitoring:

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml --profile monitoring up -d
```

Laptop-only demo **without MSK** (local Kafka):

```bash
# set MSK_BOOTSTRAP_SERVERS=kafka:29092 in .env first
make local-kafka
# or:
docker compose -f docker-compose.yml -f docker-compose.local-kafka.yml up -d --build
```

---

## Project layout

```
logops/
├── aws-infra/                 # Terraform (VPC, EC2, MSK, S3, IAM)
├── airflow/dags/              # Orchestration DAGs
├── clickhouse/init.sql        # OLAP schema
├── databricks-notebooks/      # Bronze / Silver DLT / Gold
├── dbt/logops/                # Analytics marts on Databricks
├── fluent-bit/                # Log shipper + Lua enrichment
├── grafana/                   # Datasources + dashboard JSON
├── log-generator/             # Fake JSON + nginx traffic
├── monitoring/                # Prometheus config
├── scripts/                   # setup / deploy / health-check
├── docker-compose.yml
├── docker-compose.monitoring.yml
├── .env.example
└── README.md
```

---

## Troubleshooting (5 common errors)

### 1) `Error acquiring the state lock` / Terraform fails auth
**Cause:** AWS credentials missing or wrong region.  
**Fix:** Run `aws configure` (or set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_DEFAULT_REGION`), confirm `aws sts get-caller-identity` works, re-run `bash scripts/setup-terraform.sh`.

### 2) SSH `Permission denied (publickey)`
**Cause:** Wrong key file, wrong username, or key permissions too open.  
**Fix:** Use `ec2-user` on Amazon Linux, path to the matching `.pem`, then `chmod 400 your-key.pem`. Confirm `ec2_key_pair_name` in `terraform.tfvars` matches the key pair that owns that `.pem`.

### 3) Fluent Bit / Kafka UI cannot reach MSK
**Cause:** Brokers are VPC-only; security group or wrong bootstrap string.  
**Fix:** Copy `terraform output -raw msk_bootstrap_brokers` into `.env` as `MSK_BOOTSTRAP_SERVERS`. Ensure EC2 and MSK share the VPC and MSK SG allows TCP `9092` from `var.vpc_cidr`. Restart: `docker compose up -d fluent-bit kafka-ui`.

### 4) Airflow DAG import error `ModuleNotFoundError: databricks`
**Cause:** Provider not installed in the worker image yet.  
**Fix:** `_PIP_ADDITIONAL_REQUIREMENTS` already includes `apache-airflow-providers-databricks`. Recreate workers: `docker compose up -d --force-recreate airflow-webserver airflow-scheduler airflow-worker`. Add connection `databricks_default` in the UI.

### 5) ClickHouse table missing / Grafana panels empty
**Cause:** `init.sql` only runs on first empty volume, or Gold/local processor not writing yet.  
**Fix:** `docker compose -f docker-compose.lite.yml up -d --force-recreate clickhouse-init clickhouse-seed`. Confirm log-generator + Fluent Bit + log-processor are up. For a clean wipe: `docker compose -f docker-compose.lite.yml down -v` then `.\scripts\Start-Lite.ps1`.

### 6) Docker Desktop pull errors (`http: server gave HTTP response to HTTPS client` / `tls: bad record MAC`)
**Cause:** Docker Desktop containerd snapshotter + embedded proxy corrupting large image downloads.  
**Fix:** In `%APPDATA%\Docker\settings-store.json` set `"UseContainerdSnapshotter": false`, restart Docker Desktop, then retry `docker pull` / `.\scripts\Start-Lite.ps1`. Also retry pulls 2–3 times on flaky networks.

---

## What to tell interviewers

> I built **LogOps**, an end-to-end observability pipeline. **Fluent Bit** tails JSON and nginx logs, enriches them (Lua geo mock), and publishes to **Amazon MSK**. **Databricks Spark Structured Streaming** lands raw events in a **Delta Lake Bronze** table on **S3**, a **Delta Live Tables** pipeline enforces expectations into **Silver**, and a **Gold** job computes 5-minute SLI metrics, writing to Delta and **ClickHouse** over JDBC. **Airflow (CeleryExecutor)** on **EC2** orchestrates Databricks jobs with retries, SLAs, and Slack/email failure callbacks. **dbt** builds daily marts on Databricks. **Terraform** provisions VPC, EC2, MSK, S3, and IAM. **Grafana / Superset** visualize ClickHouse metrics; optional **Prometheus + Node Exporter** cover host monitoring.

Keywords: `Airflow`, `MSK/Kafka`, `Fluent Bit`, `Spark Streaming`, `DLT`, `Delta Lake`, `S3`, `ClickHouse`, `Grafana`, `dbt`, `Terraform`, `medallion architecture`.

---

## Cost warning

MSK + `t3.large` + Databricks clusters incur ongoing AWS/Databricks charges. Tear down when done:

```bash
cd aws-infra
terraform destroy
```

Stop Databricks jobs/clusters in the Databricks UI as well
