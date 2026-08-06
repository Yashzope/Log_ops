# =============================================================================
# LogOps — Main Terraform Configuration
# Creates the network foundation: VPC, public subnets, Internet Gateway, routes.
# Everything else (EC2, MSK, S3) sits on top of this network.
# =============================================================================

# Tell Terraform which cloud provider to talk to and which region to use
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local backend stores terraform.tfstate on this machine (simple for beginners)
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Configure the AWS provider using the region from variables
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# Look up available Availability Zones so we can place subnets in different AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create an isolated virtual network (VPC) for all LogOps resources
resource "aws_vpc" "logops" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway lets resources in public subnets reach the internet
resource "aws_internet_gateway" "logops" {
  vpc_id = aws_vpc.logops.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# First public subnet (AZ 0) — used by EC2 and one MSK broker
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.logops.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a"
  }
}

# Second public subnet (AZ 1) — required because MSK needs brokers in 2+ AZs
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.logops.id
  cidr_block              = var.public_subnet_cidr_2
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-b"
  }
}

# Route table that sends all non-VPC traffic (0.0.0.0/0) to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.logops.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.logops.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Attach the public route table to subnet A
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Attach the public route table to subnet B
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
