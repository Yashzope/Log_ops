# =============================================================================
# LogOps — Amazon MSK (Managed Streaming for Apache Kafka)
# Optional: some AWS accounts need an MSK service subscription first.
# Set enable_msk = false to skip MSK and run local Kafka on EC2 instead.
# =============================================================================

# Security group for MSK brokers — only created when MSK is enabled
resource "aws_security_group" "msk" {
  count = var.enable_msk ? 1 : 0

  name        = "${var.project_name}-msk-sg"
  description = "Allow Kafka traffic to MSK brokers from the LogOps VPC"
  vpc_id      = aws_vpc.logops.id

  ingress {
    description = "Kafka plaintext from VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "MSK ZooKeeper from VPC"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-msk-sg"
  }
}

resource "aws_cloudwatch_log_group" "msk" {
  count = var.enable_msk ? 1 : 0

  name              = "/msk/${var.project_name}"
  retention_in_days = 7
}

resource "aws_msk_configuration" "logops" {
  count = var.enable_msk ? 1 : 0

  name              = "${var.project_name}-msk-config"
  kafka_versions    = [var.msk_kafka_version]
  server_properties = <<-PROPS
    auto.create.topics.enable=true
    delete.topic.enable=true
    log.retention.hours=168
    num.partitions=3
    default.replication.factor=2
    min.insync.replicas=1
  PROPS
}

resource "aws_msk_cluster" "logops" {
  count = var.enable_msk ? 1 : 0

  cluster_name           = "${var.project_name}-msk"
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = var.msk_broker_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups = [aws_security_group.msk[0].id]

    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.logops[0].arn
    revision = aws_msk_configuration.logops[0].latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk[0].name
      }
    }
  }

  tags = {
    Name = "${var.project_name}-msk"
  }
}
