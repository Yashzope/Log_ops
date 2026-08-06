# =============================================================================
# LogOps — Terraform Variables
# These are knobs you can turn without editing the main infrastructure code.
# Fill real values in terraform.tfvars (copy from terraform.tfvars.example).
# =============================================================================

# AWS region where all resources will be created
variable "aws_region" {
  description = "AWS region for LogOps infrastructure"
  type        = string
  default     = "us-east-1"
}

# Short name used as a prefix on almost every resource
variable "project_name" {
  description = "Project name prefix for tags and resource names"
  type        = string
  default     = "logops"
}

# CIDR block for the whole VPC (private IP range)
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Public subnet CIDR (hosts that need a public IP, like the EC2 Airflow host)
variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Second public subnet required by MSK (Kafka needs brokers in 2+ AZs)
variable "public_subnet_cidr_2" {
  description = "CIDR block for the second public subnet (MSK multi-AZ)"
  type        = string
  default     = "10.0.2.0/24"
}

# EC2 instance size for Airflow + Docker services
variable "ec2_instance_type" {
  description = "EC2 instance type for the Airflow host"
  type        = string
  default     = "t3.small"
}

# Create Amazon MSK? Set false if the account lacks an MSK subscription.
variable "enable_msk" {
  description = "Create Amazon MSK cluster (requires MSK service subscription)"
  type        = bool
  default     = false
}

# Name of an EXISTING EC2 key pair in your AWS account (for SSH)
variable "ec2_key_pair_name" {
  description = "Name of the existing AWS EC2 key pair used for SSH"
  type        = string
}

# Your public IP CIDR for SSH (example: 1.2.3.4/32). Use 0.0.0.0/0 only for demos.
variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into the EC2 host"
  type        = string
  default     = "0.0.0.0/0"
}

# MSK (managed Kafka) broker instance type
variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.t3.small"
}

# Number of MSK brokers (2 is the minimum for a simple multi-AZ demo)
variable "msk_broker_count" {
  description = "Number of MSK Kafka brokers"
  type        = number
  default     = 2
}

# Kafka version for MSK
variable "msk_kafka_version" {
  description = "Apache Kafka version for MSK"
  type        = string
  default     = "3.5.1"
}

# S3 bucket name for Delta Lake and archived logs (must be globally unique)
variable "s3_bucket_name" {
  description = "Globally unique S3 bucket name for Delta Lake and archives"
  type        = string
}

# Days before S3 objects transition to Glacier (cold storage)
variable "s3_glacier_transition_days" {
  description = "Days after which objects move to Glacier"
  type        = number
  default     = 90
}

# Common tags applied to every resource
variable "common_tags" {
  description = "Tags applied to all AWS resources"
  type        = map(string)
  default = {
    Project     = "LogOps"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
