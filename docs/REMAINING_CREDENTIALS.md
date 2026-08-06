# LogOps — Remaining Credentials Guide

**Status as of your current setup:** AWS, EC2, SSH key, S3, local passwords, and Grafana are already configured.  
You only need the items below if you want **Databricks / Airflow Bronze–Silver–Gold / dbt**.

The lite demo (Kafka → ClickHouse → Grafana) works **without** these.

---

## Quick checklist


| #   | Credential                         | Required?                 | Where to paste                            | Done? |
| --- | ---------------------------------- | ------------------------- | ----------------------------------------- | ----- |
| 1   | Databricks workspace host          | Yes (for Databricks path) | `.env` → `DATABRICKS_HOST`                | [ ]   |
| 2   | Databricks personal access token   | Yes (for Databricks path) | `.env` → `DATABRICKS_TOKEN`               | [ ]   |
| 3   | Databricks SQL warehouse HTTP path | Yes (for dbt)             | `dbt/logops/profiles.yml` → `http_path`   | [ ]   |
| 4   | Databricks SQL warehouse ID        | Recommended               | `.env` → `DATABRICKS_SQL_WAREHOUSE_ID`    | [ ]   |
| 5   | Databricks cluster ID              | Optional                  | `.env` → `DATABRICKS_EXISTING_CLUSTER_ID` | [ ]   |
| 6   | Bronze / Silver / Gold job IDs     | Optional                  | `.env` → `DATABRICKS_JOB_*`               | [ ]   |
| 7   | Slack webhook URL                  | Optional (alerts)         | `.env` → `SLACK_WEBHOOK_URL`              | [ ]   |
| 8   | SMTP email settings                | Optional (email alerts)   | `.env` → `AIRFLOW_SMTP_*` + `ALERT_EMAIL` | [ ]   |


---



## 1. Databricks workspace host

**What it looks like**

```text
https://adb-xxxxxxxxxxxx.azuredatabricks.net
```

or

```text
https://dbc-xxxxxxxx-xxxx.cloud.databricks.com
```

**How to get it**

1. Open your Databricks workspace in the browser.
2. Copy the URL from the address bar (only the origin — no path after the domain).
3. Keep the `https://` prefix for `.env`.

**Paste into**


| File                      | Field             | Notes                             |
| ------------------------- | ----------------- | --------------------------------- |
| `.env`                    | `DATABRICKS_HOST` | Full URL with `https://`          |
| `dbt/logops/profiles.yml` | `host`            | Hostname **only** (no `https://`) |


Example:

```env
DATABRICKS_HOST=https://adb-1234567890123456.7.azuredatabricks.net
```

```yaml
# dbt/logops/profiles.yml
host: adb-1234567890123456.7.azuredatabricks.net
```

---



## 2. Databricks personal access token (PAT)

**What it looks like**

```text
dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**How to get it**

1. In Databricks: click your user icon (top right).
2. **Settings** → **Developer** → **Access tokens** (wording may vary slightly by cloud).
3. **Generate new token**.
4. Give it a name (e.g. `logops`) and an expiry.
5. Copy the token **once** — Databricks will not show it again.

**Paste into**


| File                      | Field              |
| ------------------------- | ------------------ |
| `.env`                    | `DATABRICKS_TOKEN` |
| `dbt/logops/profiles.yml` | `token`            |


Example:

```env
DATABRICKS_TOKEN=dapiXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**Security**

- Do **not** commit this token to Git.
- Do **not** paste it into chat if you can avoid it — put it directly in the files above.
- Revoke and regenerate if it is ever exposed.

---



## 3. Databricks SQL warehouse HTTP path (required for dbt)

**What it looks like**

```text
/sql/1.0/warehouses/abc123def4567890
```

**How to get it**

1. In Databricks: **SQL** → **SQL warehouses**.
2. Open (or create) a warehouse.
3. Click **Connection details**.
4. Copy **HTTP path**.

**Paste into**


| File                      | Field       |
| ------------------------- | ----------- |
| `dbt/logops/profiles.yml` | `http_path` |


Example:

```yaml
http_path: /sql/1.0/warehouses/abc123def4567890
```

---



## 4. Databricks SQL warehouse ID (recommended)

**What it looks like**

```text
abc123def4567890
```

(Same ID as the last segment of the HTTP path.)

**How to get it**

From the warehouse **Connection details**, or from the warehouse URL / HTTP path.

**Paste into**

```env
DATABRICKS_SQL_WAREHOUSE_ID=abc123def4567890
```

---



## 5. Optional — existing cluster ID

Only needed if Airflow/notebooks should use a fixed all-purpose cluster.

**How to get it**

1. **Compute** → open your cluster.
2. Copy the **Cluster ID** from the page URL or details panel.

```env
DATABRICKS_EXISTING_CLUSTER_ID=0123-456789-abcdefg
```

Leave blank if you use job clusters / SQL warehouse only.

---



## 6. Optional — Bronze / Silver / Gold job IDs

Only needed after you create Databricks Jobs / a DLT pipeline and want Airflow to trigger them by ID.


| `.env` key                     | Meaning                      |
| ------------------------------ | ---------------------------- |
| `DATABRICKS_JOB_BRONZE_ID`     | Bronze streaming job ID      |
| `DATABRICKS_JOB_SILVER_DLT_ID` | Silver DLT pipeline / job ID |
| `DATABRICKS_JOB_GOLD_ID`       | Gold aggregations job ID     |


**How to get them**

1. **Workflows** → **Jobs** (or **Delta Live Tables**).
2. Open the job/pipeline → copy the numeric ID from the URL or details.

You can leave these as `0` until those jobs exist.

---



## 7. Optional — Slack webhook (alerts)

**How to get it**

1. In Slack: create an Incoming Webhook for your channel.
2. Copy the webhook URL.

```env
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T000/B000/XXXX
```

Leave empty if you do not want Slack alerts.

---



## 8. Optional — SMTP / email alerts


| `.env` key               | Example                                  |
| ------------------------ | ---------------------------------------- |
| `AIRFLOW_SMTP_HOST`      | `smtp.gmail.com`                         |
| `AIRFLOW_SMTP_USER`      | your email                               |
| `AIRFLOW_SMTP_PASSWORD`  | app password (not normal Gmail password) |
| `AIRFLOW_SMTP_MAIL_FROM` | same email                               |
| `ALERT_EMAIL`            | where alerts should go                   |


Leave the current `localhost` / `local` values if you do not need email.

---



## After you fill them in

1. Edit `.env` and `dbt/logops/profiles.yml` with the values above.
2. Restart the full stack if Airflow is running (Databricks env vars are read at container start).
3. Unpause the Databricks-related Airflow DAGs only after host + token are valid.
4. For dbt:

```powershell
cd C:\Users\91741\Downloads\logops\dbt\logops
dbt debug
dbt run
```

---



## Already configured (do not send again)

These are **done** on your machine — no action needed for the remaining-credentials path:


| Item                                     | Value / location                       |
| ---------------------------------------- | -------------------------------------- |
| AWS CLI credentials                      | Configured for account `437323115586`  |
| AWS region                               | `ap-south-1`                           |
| EC2 public IP                            | `13.127.143.187` (in `.env`)           |
| SSH PEM                                  | `C:\Users\91741\logops-key.pem`        |
| S3 bucket                                | `logops-delta-437323115586-ap-south-1` |
| Grafana / Airflow / ClickHouse passwords | Generated in `.env`                    |
| Terraform `terraform.tfvars`             | No remaining `FILL_IN`                 |


---



## Minimum paste set (copy/fill)

Use this block when you are ready. Replace the bracketed values, then copy into `.env`:

```env
DATABRICKS_HOST=[FILL_IN_YOUR_DATABRICKS_HOST]
DATABRICKS_TOKEN=[FILL_IN_YOUR_DATABRICKS_TOKEN]
DATABRICKS_SQL_WAREHOUSE_ID=[FILL_IN_YOUR_DATABRICKS_SQL_WAREHOUSE_ID]
```

And into `dbt/logops/profiles.yml`:

```yaml
host: [FILL_IN_YOUR_DATABRICKS_HOST_WITHOUT_HTTPS]
token: [FILL_IN_YOUR_DATABRICKS_TOKEN]
http_path: [FILL_IN_YOUR_DATABRICKS_HTTP_PATH]
```

---



## Need help?

If you have a Databricks workspace already, send only:

1. Whether it is **AWS / Azure / GCP** Databricks
2. That you created a **SQL warehouse** (yes/no)

Do **not** paste the live token into chat unless you intend to rotate it afterward.