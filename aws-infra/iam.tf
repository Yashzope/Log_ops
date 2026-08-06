# =============================================================================
# LogOps — IAM Role for the EC2 Airflow Host
# Lets the instance read/write S3 and talk to MSK without embedding AWS keys.
# =============================================================================

# Trust policy: only EC2 instances may assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# The IAM role attached to the EC2 instance
resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# Permissions: S3 read/write on the Delta Lake bucket + MSK describe/connect
data "aws_iam_policy_document" "ec2_permissions" {
  # Allow listing and reading/writing objects in the LogOps S3 bucket
  statement {
    sid    = "S3DeltaLakeAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = [
      aws_s3_bucket.delta_lake.arn,
      "${aws_s3_bucket.delta_lake.arn}/*"
    ]
  }

  # Allow the host to discover and connect to the MSK cluster
  statement {
    sid    = "MSKAccess"
    effect = "Allow"
    actions = [
      "kafka:DescribeCluster",
      "kafka:DescribeClusterV2",
      "kafka:GetBootstrapBrokers",
      "kafka:ListClusters",
      "kafka:ListClustersV2",
      "kafka:ListNodes",
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:AlterCluster",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:CreateTopic",
      "kafka-cluster:WriteData",
      "kafka-cluster:ReadData",
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup"
    ]
    resources = ["*"]
  }

  # Allow reading CloudWatch logs for MSK debugging from the host if needed
  statement {
    sid    = "CloudWatchLogsRead"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents"
    ]
    resources = ["*"]
  }
}

# Attach the permissions document as a managed inline policy on the role
resource "aws_iam_role_policy" "ec2_policy" {
  name   = "${var.project_name}-ec2-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

# Instance profile is the "glue" that attaches the IAM role to EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
