# LogOps – Observability & Log Analytics Platform

LogOps is an end-to-end observability and log analytics platform designed to collect, process, transform, and visualize application log data in near real time.

The platform uses Apache Kafka for event streaming, Databricks and Apache Spark for distributed data processing, Delta Lake for data storage, Apache Airflow for workflow orchestration, and ClickHouse for analytical queries and dashboard visualization.

## Architecture

```text
       Application Logs / Nginx
                 |
                 v
             Fluent Bit
                 |
                 v
          AWS MSK (Kafka)
                 |
                 v
     Spark Structured Streaming
                 |
                 v
          Bronze Layer
          (Raw Events)
                 |
                 v
           Silver Layer
       (Cleaned & Validated)
                 |
                 v
            Gold Layer
       (Aggregated Metrics)
                 |
                 v
             ClickHouse
                 |
          +------+------+
          |             |
          v             v
       Grafana       Superset


    Apache Airflow
    (Orchestration)

    Terraform
    (Infrastructure)

    Amazon S3
    (Data Storage)

    dbt
    (Analytics Models)
```

## Technology Stack

| Category | Technologies |
|---|---|
| Log Collection | Fluent Bit, Lua |
| Event Streaming | Apache Kafka, AWS MSK |
| Data Processing | Apache Spark, Databricks |
| Data Transformation | Delta Live Tables |
| Data Storage | Delta Lake, Amazon S3 |
| Workflow Orchestration | Apache Airflow |
| Analytical Database | ClickHouse |
| Data Modeling | dbt |
| Visualization | Grafana, Apache Superset |
| Infrastructure as Code | Terraform |
| Cloud Platform | Amazon Web Services |

## Key Features

- Application and Nginx log collection.
- Real-time log ingestion through Apache Kafka.
- Distributed stream processing using Spark Structured Streaming.
- Medallion architecture with Bronze, Silver, and Gold layers.
- Data cleansing and validation using Delta Live Tables.
- Five-minute aggregation of operational metrics.
- Analytical data storage using ClickHouse.
- Workflow orchestration using Apache Airflow.
- Analytics modeling using dbt.
- Interactive dashboards using Grafana and Superset.
- AWS infrastructure provisioning using Terraform.

## Data Processing Workflow

### 1. Log Collection

Fluent Bit collects application and Nginx logs, performs log enrichment, and forwards events to Apache Kafka.

### 2. Event Streaming

Amazon MSK provides the Kafka-based streaming infrastructure for handling incoming log events.

### 3. Bronze Layer

Spark Structured Streaming consumes Kafka events and stores raw log records in Delta Lake on Amazon S3.

### 4. Silver Layer

Delta Live Tables processes raw records, performs data cleansing, and applies data quality expectations to produce validated datasets.

### 5. Gold Layer

The Gold layer generates five-minute aggregations and operational metrics from the processed log data.

### 6. Analytics and Visualization

Aggregated metrics are written to ClickHouse and made available to Grafana and Apache Superset for dashboard visualization and analytical reporting.

### 7. Workflow Orchestration

Apache Airflow manages the data processing workflows, including Bronze, Silver, Gold, and maintenance operations.

## Project Structure

```text
logops/
│
├── aws-infra/              # AWS infrastructure using Terraform
│
├── airflow/
│   └── dags/               # Airflow orchestration workflows
│
├── clickhouse/
│   └── init.sql            # ClickHouse database schema
│
├── databricks-notebooks/   # Bronze, Silver and Gold processing
│
├── dbt/
│   └── logops/             # Analytics models
│
├── fluent-bit/             # Log collection and enrichment
│
├── grafana/                # Dashboards and data sources
│
├── log-generator/          # Application log generation
│
├── monitoring/             # Monitoring configurations
│
└── scripts/                # Project utility scripts
```

## Data Architecture

The project follows the Medallion Architecture to organize and process log data through three layers:

| Layer | Purpose | Output |
|---|---|---|
| Bronze | Raw log ingestion | Raw Delta tables |
| Silver | Data cleansing and validation | Clean Delta tables |
| Gold | Metric aggregation and analytics | Aggregated Delta tables |

## Project Objectives

- Build a scalable log ingestion and processing pipeline.
- Implement real-time event streaming with Apache Kafka.
- Apply distributed data processing using Apache Spark.
- Organize data using the Medallion Architecture.
- Automate data workflows using Apache Airflow.
- Enable analytical querying and visualization of operational metrics.

---

**LogOps – Observability and Log Analytics Platform**
