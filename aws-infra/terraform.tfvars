# Auto-prepared for Free Tier friendly deploy (MSK disabled — use local Kafka on EC2)
aws_region     = "ap-south-1"
project_name   = "logops"

ec2_key_pair_name = "logops-key"
ssh_allowed_cidr  = "14.139.112.69/32"

s3_bucket_name = "logops-delta-437323115586-ap-south-1"

# Free Tier eligible in ap-south-1 (t3.large was blocked on this account)
ec2_instance_type = "t3.small"

# MSK subscription not enabled on this account yet
enable_msk = false

msk_instance_type          = "kafka.t3.small"
msk_broker_count           = 2
msk_kafka_version          = "3.5.1"
s3_glacier_transition_days = 90
vpc_cidr                   = "10.0.0.0/16"
public_subnet_cidr         = "10.0.1.0/24"
public_subnet_cidr_2       = "10.0.2.0/24"

common_tags = {
  Project     = "LogOps"
  Environment = "dev"
  ManagedBy   = "terraform"
  Owner       = "Admin"
}
