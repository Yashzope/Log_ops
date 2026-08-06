# =============================================================================
# LogOps — Terraform Outputs
# After `terraform apply`, these values print so you can copy them into .env
# and Fluent Bit / Databricks configs.
# =============================================================================

output "ec2_public_ip" {
  description = "Public IP address of the Airflow EC2 host"
  value       = aws_instance.airflow_host.public_ip
}

output "ec2_ssh_command" {
  description = "Example SSH command to connect to the Airflow host"
  value       = "ssh -i $env:USERPROFILE/logops-key.pem ec2-user@${aws_instance.airflow_host.public_ip}"
}

# Empty string when enable_msk=false — use local Kafka on EC2 instead
output "msk_bootstrap_brokers" {
  description = "MSK Kafka bootstrap broker URLs (plaintext), or empty if MSK disabled"
  value       = var.enable_msk ? aws_msk_cluster.logops[0].bootstrap_brokers : ""
}

output "msk_enabled" {
  description = "Whether Amazon MSK was provisioned"
  value       = var.enable_msk
}

output "kafka_mode_hint" {
  description = "How to run Kafka for this deployment"
  value       = var.enable_msk ? "Use MSK brokers from msk_bootstrap_brokers" : "MSK disabled — on EC2 run: docker compose -f docker-compose.lite.yml up -d"
}

output "s3_bucket_name" {
  description = "S3 bucket name for Delta Lake and archives"
  value       = aws_s3_bucket.delta_lake.id
}

output "s3_delta_root" {
  description = "Suggested S3 root path for Delta Lake tables"
  value       = "s3://${aws_s3_bucket.delta_lake.id}/delta/"
}

output "vpc_id" {
  description = "LogOps VPC ID"
  value       = aws_vpc.logops.id
}

output "ec2_security_group_id" {
  description = "Security group ID of the Airflow EC2 host"
  value       = aws_security_group.airflow_host.id
}

output "msk_security_group_id" {
  description = "Security group ID of the MSK cluster (null if disabled)"
  value       = var.enable_msk ? aws_security_group.msk[0].id : null
}

output "ui_urls" {
  description = "Browser URLs for LogOps UIs after docker-compose is running"
  value = {
    airflow  = "http://${aws_instance.airflow_host.public_ip}:8080"
    grafana  = "http://${aws_instance.airflow_host.public_ip}:3000"
    superset = "http://${aws_instance.airflow_host.public_ip}:8088"
    kafka_ui = "http://${aws_instance.airflow_host.public_ip}:8081"
  }
}
