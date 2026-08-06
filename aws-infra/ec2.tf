# =============================================================================
# LogOps — EC2 Airflow Host
# A single Amazon Linux 2023 t3.large that runs Docker Compose services
# (Airflow, ClickHouse, Grafana, Superset, Fluent Bit, Kafka UI, etc.).
# =============================================================================

# Find the latest Amazon Linux 2023 AMI in this region (so we don't hard-code IDs)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group = firewall rules for the EC2 instance
resource "aws_security_group" "airflow_host" {
  name        = "${var.project_name}-airflow-host-sg"
  description = "Allow SSH and LogOps UI ports into the Airflow EC2 host"
  vpc_id      = aws_vpc.logops.id

  # SSH — so you can log in and run setup scripts
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Airflow web UI
  ingress {
    description = "Airflow webserver"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana dashboards
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Apache Superset
  ingress {
    description = "Superset"
    from_port   = 8088
    to_port     = 8088
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ClickHouse HTTP interface (Grafana / curl queries use 8123)
  ingress {
    description = "ClickHouse HTTP"
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ClickHouse native TCP interface
  ingress {
    description = "ClickHouse native"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kafka / Kafka UI related traffic from VPC (and optional public access for demos)
  ingress {
    description = "Kafka / Kafka UI"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr, "0.0.0.0/0"]
  }

  # Kafka UI web port (often 8081; keep 9092 open as requested; also open 8081)
  ingress {
    description = "Kafka UI web"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound so Docker can pull images and talk to AWS APIs
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-airflow-host-sg"
  }
}

# User-data script runs once on first boot to install Docker basics
locals {
  ec2_user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    # Update packages and install Docker so Compose can start later
    dnf update -y
    dnf install -y docker git
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /var/log/logops /opt/logops
    chmod 755 /var/log/logops /opt/logops
  EOF
}

# The EC2 instance that hosts Airflow and the Docker stack
resource "aws_instance" "airflow_host" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public_a.id
  key_name               = var.ec2_key_pair_name
  vpc_security_group_ids = [aws_security_group.airflow_host.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  user_data              = local.ec2_user_data

  # Keep disk within typical Free Tier friendly size while leaving room for images
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-airflow-host"
  }
}
