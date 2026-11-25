# LogOps — Observability & Log Analytics Platform

LogOps is an end-to-end log collection, processing, orchestration, and visualization project. It collects application and Nginx logs, streams them through Kafka, processes them with Databricks and Delta Lake, creates analytics metrics, and displays those metrics through Grafana and Superset.

The project includes two ways to run the pipeline:

- **Local demo:** Run a lightweight version on your computer with Docker Desktop. This path does not require an AWS account or Databricks.
- **AWS deployment:** Provision cloud infrastructure with Terraform, use Amazon MSK for Kafka, process data with Databricks, and orchestrate the workflow with Airflow.

> **Important:** AWS MSK, EC2, and Databricks resources can generate ongoing charges. Review the estimated costs before deployment and shut down resources when you finish.

---

## Contents

- [Project overview](#project-overview)
- [Architecture](#architecture)
- [How the pipeline works](#how-the-pipeline-works)
- [Technology stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Run the local demo](#run-the-local-demo)
- [Deploy to AWS](#deploy-to-aws)
- [Access the application interfaces](#access-the-application-interfaces)
- [Project structure](#project-structure)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Interview explanation](#interview-explanation)
- [Clean up cloud resources](#clean-up-cloud-resources)

---

## Project overview

LogOps demonstrates how an observability and log analytics platform can be built using an event-streaming and lakehouse architecture.

It is designed to show how log data can move through a complete data pipeline:

1. Generate application and Nginx log events.
2. Collect and enrich the logs using Fluent Bit.
3. Send events to Kafka.
4. Store raw events in a Bronze Delta table.
5. validate and clean records in the Silver layer.
6. Create aggregated metrics in the Gold layer.
7. Load metrics into ClickHouse for analytics.
8. Visualize the results in Grafana and Superset.
9. Orchestrate pipeline tasks with Apache Airflow.

The project follows the **Medallion Architecture** using Bronze, Silver, and Gold data layers.

## Architecture

```text
              Application / Nginx Log Generator
                            |
                            v
                    Fluent Bit + Lua
                 (collect and enrich logs)
                            |
                            v
                       Kafka / MSK
                            |
             +--------------+--------------+
             |                             |
             v                             v
     Spark Structured                 Kafka UI
        Streaming                  (optional UI)
             |
             v
     +------------------+
     | Bronze Layer     |
     | Delta: bronze.raw|
     | Raw log events   |
     +--------+---------+
              |
              v
     +------------------+
     | Silver Layer     |
     | Delta Live Tables|
     | Delta: silver.clean
     | Validated records|
     +--------+---------+
              |
              v
     +------------------+
     | Gold Layer       |
     | 5-minute metrics |
     | Delta on S3      |
     +--------+---------+
              |
              | JDBC / foreachBatch
              v
         ClickHouse
       (metrics_5min)
              |
        +-----+------+
        |            |
        v            v
     Grafana      Superset

   Apache Airflow orchestrates pipeline jobs.
   Terraform provisions AWS infrastructure.
   dbt builds analytics marts on Databricks.
```

### Local demo architecture

The lightweight local setup uses a local Kafka broker and a local processor in place of the AWS MSK and Databricks services:

```text
Log Generator
     |
     v
 Fluent Bit
     |
     v
 Local Kafka
     |
     v
 Log Processor
     |
     v
 ClickHouse
     |
     v
 Grafana
```

The local `log-processor/` component performs the metrics-writing role that the Databricks Gold layer performs in the AWS setup. This allows the local Grafana dashboard to display data without requiring Databricks.

## How the pipeline works

### 1. Log generation

The `log-generator/` component creates sample JSON application logs and Nginx-style traffic logs. The local demo can also use the NASA HTTP public dataset through the provided download script.

### 2. Log collection and enrichment

Fluent Bit reads the generated log files and forwards events to Kafka. Lua is used for log enrichment.

### 3. Event streaming

Kafka acts as the message broker between log collection and processing.

- In the AWS deployment, the pipeline uses **Amazon MSK**.
- In the local demo, the pipeline can use a local Kafka service.

### 4. Bronze layer — raw data

Databricks Spark Structured Streaming reads Kafka events and stores the raw records in the Bronze Delta table:

`bronze.raw`

This layer retains the incoming log data for downstream processing.

### 5. Silver layer — cleaned data

A Delta Live Tables (DLT) pipeline applies expectations and validation rules to the incoming records. The cleaned data is stored in:

`silver.clean`

### 6. Gold layer — aggregated metrics

The Gold processing job calculates five-minute service-level indicator (SLI) aggregations. The results are stored in Delta Lake on Amazon S3 and written to ClickHouse using JDBC with `foreachBatch`.

### 7. Analytics and dashboards

ClickHouse stores the aggregated metrics in the `metrics_5min` table. Grafana and Superset are used to explore and visualize the metrics.

### 8. Orchestration

Apache Airflow runs on EC2 with Docker and coordinates the Bronze, Silver, Gold, and VACUUM workflows. The project includes Airflow DAGs for the pipeline.

### 9. Infrastructure

Terraform provisions the AWS resources used by the cloud deployment, including the VPC, EC2, MSK, S3, and IAM resources.

---

## Technology stack

| Technology | Purpose in this project |
|---|---|
| Python | Log generation and processing scripts |
| Fluent Bit | Collects and forwards log events |
| Lua | Enriches log records |
| Apache Kafka | Streams log events |
| Amazon MSK | Managed Kafka service in AWS |
| Apache Spark Structured Streaming | Reads and processes streaming data |
| Databricks | Runs the data processing workloads |
| Delta Live Tables | Applies data expectations in the Silver layer |
| Delta Lake | Stores Bronze, Silver, and Gold data |
| Amazon S3 | Stores Delta Lake data |
| Apache Airflow | Orchestrates pipeline workflows |
| ClickHouse | Stores aggregated metrics for analytics |
| dbt | Builds analytics marts on Databricks |
| Grafana | Visualizes metrics through dashboards |
| Apache Superset | Provides analytics and visualization |
| Terraform | Provisions AWS infrastructure |
| Docker / Docker Compose | Runs project services and application components |
| Prometheus / Node Exporter | Optional host monitoring |

---

## Prerequisites

### For the local demo

- Docker Desktop installed and running.
- Git, if you are cloning the project.
- PowerShell for the provided Windows `.ps1` scripts.

### For the AWS deployment

- An AWS account with permission to create VPC, EC2, MSK, S3, and IAM resources.
- An EC2 key pair in the AWS region you plan to use. Keep the matching `.pem` file available.
- AWS CLI installed and configured.
- Terraform version 1.5 or later.
- Git and SSH.
- `rsync` if required by your deployment workflow.
- A Databricks workspace on AWS with permission to create jobs, Delta Live Tables pipelines, and a SQL warehouse.
- Sufficient AWS quota for a `t3.large` EC2 instance and two `kafka.t3.small` brokers.

---

## Run the local demo

The local demo is the recommended way to verify the project before creating AWS resources. It does not require AWS or Databricks.

### Option A: Lightweight local stack

**Requirement:** Docker Desktop.

Open PowerShell in the project directory and run:

```powershell
.\scripts\Start-Lite.ps1
```

This starts the lightweight pipeline:

`log-generator → Fluent Bit → local Kafka → log-processor → ClickHouse → Grafana`

Open Grafana:

- URL: `http://localhost:3000`
- The script prints the login credentials.
- Navigate to **Dashboards → LogOps Overview**.

To open Grafana and Kafka UI and copy the Grafana password to the clipboard:

```powershell
.\scripts\Open-Local.ps1
```

To verify the local services:

```powershell
.\scripts\Verify-Local.ps1
```

To stop the lightweight stack:

```powershell
docker compose -f docker-compose.lite.yml down
```

### Option B: Run with the NASA HTTP dataset

The project also provides scripts to download and run the selected NASA HTTP public dataset.

```powershell
.\scripts\Download-Nasa.ps1
.\scripts\Start-Lite-Nasa.ps1
```

For dataset details, refer to:

- `docs/PROBLEM_STATEMENT.md`
- `docs/DATASETS.md`

### Option C: Full local stack with Airflow

To start the full local setup, including Airflow:

```powershell
.\scripts\Start-Local.ps1
```

**Note:** Airflow DAGs that call Databricks will remain paused or fail until valid Databricks credentials and configuration are added. This is expected when running locally without Databricks.

### Local demo helper scripts

The project includes scripts to explain the pipeline, show interview talking points, and check the EC2 deployment status:

```powershell
.\scripts\Explain-Pipeline.ps1
.\scripts\Show-Interview-Talking-Points.ps1
.\scripts\Status-Ec2.ps1
```

---

## Deploy to AWS

Deploying to AWS creates billable infrastructure. First make sure the local lightweight demo works, then review the Terraform plan before applying it.

### 1. Configure AWS credentials

Configure the AWS CLI if you have not already done so:

```bash
aws configure
```

Check that the CLI can identify your AWS account:

```bash
aws sts get-caller-identity
```

### 2. Create the environment configuration

For Windows PowerShell:

```powershell
.\scripts\Generate-Secrets.ps1
```

For Linux, macOS, Git Bash, or WSL:

```bash
bash scripts/generate-secrets.sh
```

These scripts help create the `.env` file and generate passwords. If you prefer to configure it manually:

```bash
cp .env.example .env
```

Edit `.env` and replace the `[FILL_IN_YOUR_XXX]` placeholders with the required values. These include application passwords and Databricks host/token details. A Slack webhook can be added if you use one.

Do not commit `.env` or other files containing credentials to source control.

### 3. Configure Terraform variables

From the project root:

**PowerShell:**

```powershell
Copy-Item aws-infra\terraform.tfvars.example aws-infra\terraform.tfvars
notepad aws-infra\terraform.tfvars
```

**Linux / macOS / Git Bash / WSL:**

```bash
cd aws-infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and replace all placeholders. The configuration includes values such as:

- AWS region
- EC2 key pair name
- SSH CIDR range
- Unique S3 bucket name

Use `FILL_IN_CHECKLIST.txt` to track the required configuration values.

If you do not already have an EC2 key pair, create one in the target AWS region before continuing.

### 4. Prepare AWS-specific values

On Windows PowerShell, you can run:

```powershell
.\scripts\Prepare-Aws.ps1
```

This script creates `aws-infra/terraform.tfvars` with values such as the region, a suggested S3 bucket name, and SSH CIDR information. If a key pair is missing, the script prints a command to help create one.

### 5. Review the Terraform plan

**PowerShell:**

```powershell
.\scripts\Setup-Terraform.ps1
```

**Linux / macOS / Git Bash / WSL:**

```bash
bash scripts/setup-terraform.sh
```

Review the plan carefully before applying it. EC2 and MSK resources can incur ongoing charges.

### 6. Provision infrastructure and deploy

**Windows PowerShell:**

```powershell
.\scripts\Deploy-Windows.ps1
```

**Linux / macOS / Git Bash / WSL:**

```bash
bash scripts/deploy.sh
```

The deployment script performs the following operations:

1. Applies the Terraform configuration.
2. Copies project files to the EC2 instance under `/opt/logops`.
3. Installs Docker if it is not already installed.
4. Starts the application services using Docker Compose.

After Terraform completes, note the outputs, especially:

- `ec2_public_ip`
- `msk_bootstrap_brokers`
- `s3_bucket_name`

The deployment scripts may populate some AWS-specific values in `.env`. Check the file before starting or restarting services.

### 7. Manual EC2 deployment (alternative)

If you prefer not to use the deployment script, apply Terraform manually:

```bash
cd aws-infra
terraform apply
```

Copy the project to EC2, then connect using your key pair:

```bash
ssh -i [YOUR_KEY_FILE].pem ec2-user@[YOUR_EC2_PUBLIC_IP]
```

After copying the repository to the EC2 instance, run:

```bash
sudo bash /opt/logops/scripts/setup-aws-linux.sh
cd /opt/logops
cp .env.example .env
```

Update `.env` with the required broker URL and application secrets. Then run:

```bash
export AIRFLOW_UID=$(id -u)
docker compose up -d --build
```

### 8. Import Databricks notebooks

In the Databricks workspace:

1. Open **Workspace**.
2. Create a folder named `logops`.
3. Import the following notebooks:

| Notebook | Purpose |
|---|---|
| `databricks-notebooks/01_bronze_streaming.py` | Reads streaming events and writes the Bronze data |
| `databricks-notebooks/02_silver_dlt.py` | Defines the Silver Delta Live Tables pipeline |
| `databricks-notebooks/03_gold_aggregations.py` | Calculates Gold-layer aggregations |

Configure the Databricks jobs and DLT pipeline. Add the corresponding job and pipeline IDs to `.env`.

### 9. Configure the Airflow connection

Open the Airflow interface:

`http://[EC2_PUBLIC_IP]:8080`

In Airflow:

1. Navigate to **Admin → Connections**.
2. Create a connection with the ID `databricks_default`.
3. Enter the Databricks host and token.
4. Save the connection.
5. Unpause the `logops_*` DAGs.

### 10. Verify the deployment

Connect to EC2 and run:

```bash
bash /opt/logops/scripts/health-check.sh
```

You can also use the local helper script to check EC2 status:

```powershell
.\scripts\Status-Ec2.ps1
```

### Optional: Enable monitoring

To start the optional monitoring services:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.monitoring.yml \
  --profile monitoring up -d
```

The optional monitoring configuration includes Prometheus and Node Exporter for host monitoring.

### Optional: Use local Kafka instead of Amazon MSK

For a laptop-only run of the full Compose setup without MSK, set the following value in `.env`:

```env
MSK_BOOTSTRAP_SERVERS=kafka:29092
```

Then run either:

```bash
make local-kafka
```

or:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.local-kafka.yml \
  up -d --build
```

---

## Access the application interfaces

For an AWS deployment, replace `[EC2_PUBLIC_IP]` with the public IP address of your EC2 instance.

| Service | URL | Purpose |
|---|---|---|
| Airflow | `http://[EC2_PUBLIC_IP]:8080` | Manage and monitor pipeline workflows |
| Grafana | `http://[EC2_PUBLIC_IP]:3000` | View dashboards and metrics |
| Superset | `http://[EC2_PUBLIC_IP]:8088` | Explore analytics |
| Kafka UI | `http://[EC2_PUBLIC_IP]:8081` | Inspect Kafka topics and messages |

For the local lightweight demo, Grafana is available at:

`http://localhost:3000`

The local scripts print the required credentials.

### Access EC2 services through an SSH tunnel

If your network blocks ports such as 3000 or 8081, use the provided SSH tunnel script:

```powershell
.\scripts\Open-Ec2-Tunnel.ps1
```

Then open:

- Grafana: `http://localhost:3000`
- Kafka UI: `http://localhost:8081`

To redeploy the lightweight stack to EC2:

```powershell
.\scripts\Deploy-Lite-Ec2.ps1
```

---

## Project structure

```text
logops/
├── aws-infra/                 # Terraform: VPC, EC2, MSK, S3, IAM
├── airflow/
│   └── dags/                  # Airflow orchestration DAGs
├── clickhouse/
│   └── init.sql               # ClickHouse analytics schema
├── databricks-notebooks/      # Bronze, Silver DLT, and Gold notebooks
├── dbt/
│   └── logops/                # Analytics marts on Databricks
├── fluent-bit/                # Log collection and Lua enrichment
├── grafana/                   # Grafana datasources and dashboard JSON
├── log-generator/             # Sample JSON and Nginx traffic logs
├── monitoring/                # Prometheus configuration
├── scripts/                   # Setup, deployment, and health-check scripts
├── docker-compose.yml         # Main Docker Compose configuration
├── docker-compose.monitoring.yml
├── .env.example               # Environment variable template
└── README.md                  # Project documentation
```

---

## Configuration

The project uses environment variables and Terraform variables to keep deployment-specific settings outside the application code.

### Important configuration files

| File | What it configures |
|---|---|
| `.env.example` | Template for application credentials and service settings |
| `.env` | Your local deployment settings and secrets |
| `aws-infra/terraform.tfvars.example` | Example AWS infrastructure variables |
| `aws-infra/terraform.tfvars` | Your AWS infrastructure settings |
| `FILL_IN_CHECKLIST.txt` | Checklist of values that need to be supplied |

### Security notes

- Keep `.env`, Terraform state files, private keys, and access tokens out of public repositories.
- Do not paste AWS secret access keys, Databricks tokens, or passwords into README files or screenshots.
- Restrict the SSH CIDR range to trusted IP addresses rather than opening SSH access broadly.
- Review security-group rules before deploying services.

---

## Troubleshooting

### 1. Terraform state lock or AWS authentication error

**Possible cause:** AWS credentials are missing or incorrect, or the selected region is wrong.

**What to check:**

```bash
aws configure
aws sts get-caller-identity
```

Confirm that the expected AWS account and region are being used, then rerun the Terraform setup script:

```bash
bash scripts/setup-terraform.sh
```

### 2. SSH error: `Permission denied (publickey)`

**Possible causes:**

- The wrong `.pem` file is being used.
- The EC2 username is incorrect.
- The key pair configured in Terraform does not match the private key.

**What to check:**

- Use `ec2-user` for the Amazon Linux instance described by this project.
- Confirm `ec2_key_pair_name` in `terraform.tfvars` matches your key pair.
- On Linux, macOS, Git Bash, or WSL, restrict the key file permissions:

```bash
chmod 400 your-key.pem
```

### 3. Fluent Bit or Kafka UI cannot connect to Amazon MSK

**Possible causes:** MSK is reachable only within the configured VPC, the security-group rules are incorrect, or the bootstrap-server value is wrong.

**What to check:**

Get the broker address:

```bash
cd aws-infra
terraform output -raw msk_bootstrap_brokers
```

Set the returned value as `MSK_BOOTSTRAP_SERVERS` in `.env`. Confirm that EC2 and MSK are in the same VPC and that the MSK security group allows TCP port `9092` from the configured VPC CIDR.

Restart the relevant services:

```bash
docker compose up -d fluent-bit kafka-ui
```

### 4. Airflow error: `ModuleNotFoundError: databricks`

**Possible cause:** The Databricks Airflow provider is not installed in the running Airflow containers.

The project configuration includes `apache-airflow-providers-databricks` through `_PIP_ADDITIONAL_REQUIREMENTS`. Recreate the Airflow containers:

```bash
docker compose up -d --force-recreate \
  airflow-webserver airflow-scheduler airflow-worker
```

Also confirm that the `databricks_default` connection exists in Airflow.

### 5. ClickHouse table is missing or Grafana panels are empty

**Possible causes:**

- The ClickHouse initialization script has not run for the current data volume.
- The Gold job or local processor has not written metrics yet.
- The log generator or Fluent Bit is not running.

For the lightweight local stack, recreate the initialization and seed services:

```bash
docker compose -f docker-compose.lite.yml up -d --force-recreate \
  clickhouse-init clickhouse-seed
```

Confirm that the log generator, Fluent Bit, and log processor are running.

**Warning:** The following command removes the lightweight stack's Docker volumes and stored local data:

```bash
docker compose -f docker-compose.lite.yml down -v
```

Afterward, start the local stack again:

```powershell
.\scripts\Start-Lite.ps1
```

### 6. Docker Desktop image pull errors

Examples:

- `http: server gave HTTP response to HTTPS client`
- `tls: bad record MAC`

**Possible cause:** Docker Desktop's containerd snapshotter or embedded proxy may be interfering with large image downloads, or the network connection may be unstable.

**Possible steps:**

1. Open `%APPDATA%\Docker\settings-store.json`.
2. If the setting is present, set `"UseContainerdSnapshotter": false`.
3. Restart Docker Desktop.
4. Retry the image pull or run the local start script again.

On an unstable network, retrying the image pull may also help.

---

## Interview explanation

You can use the following explanation to describe the project in an interview:

> I built LogOps, an end-to-end observability and log analytics pipeline. Fluent Bit collects JSON and Nginx logs, enriches them using Lua, and publishes them to Amazon MSK. Databricks Spark Structured Streaming reads the events and stores the raw data in a Bronze Delta Lake table on S3. A Delta Live Tables pipeline applies expectations and creates the Silver layer. A Gold job calculates five-minute SLI metrics and writes the results to Delta Lake and ClickHouse using JDBC. Apache Airflow, running with CeleryExecutor on EC2, orchestrates the Databricks workflows with retries, SLAs, and Slack or email failure callbacks. dbt builds daily analytics marts on Databricks. Terraform provisions the VPC, EC2, MSK, S3, and IAM resources. Finally, Grafana and Superset visualize the ClickHouse metrics, while optional Prometheus and Node Exporter components support host monitoring.

### Key concepts to remember

- Log collection and enrichment
- Event streaming with Kafka / Amazon MSK
- Spark Structured Streaming
- Medallion Architecture: Bronze, Silver, and Gold
- Delta Lake and Delta Live Tables
- Data orchestration with Apache Airflow
- Analytics with ClickHouse and dbt
- Dashboards with Grafana and Superset
- Infrastructure as Code with Terraform
- AWS services: EC2, S3, MSK, VPC, and IAM

---

## Clean up cloud resources

AWS MSK, EC2, and Databricks clusters or jobs may continue to incur charges while they are running.

When you have finished using the AWS deployment, destroy the Terraform-managed infrastructure:

```bash
cd aws-infra
terraform destroy
```

Review the Terraform destroy plan before confirming it.

Also stop Databricks jobs and clusters from the Databricks workspace. Check for any other billable resources that may have been created separately from Terraform.

For the local lightweight stack, stop the containers with:

```powershell
docker compose -f docker-compose.lite.yml down
```

---

## Project notes

- The lightweight local processor is used to make the local dashboard work without Databricks.
- The AWS pipeline uses Databricks Gold processing to write aggregated metrics to ClickHouse.
- Databricks-connected Airflow DAGs require valid Databricks credentials and a configured Airflow connection.
- The NASA HTTP dataset is an optional input for the local demo.
