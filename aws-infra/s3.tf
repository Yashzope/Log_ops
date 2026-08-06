# =============================================================================
# LogOps — S3 Bucket for Delta Lake + Log Archives
# Stores Bronze/Silver/Gold Delta tables and old log archives.
# A lifecycle rule moves aging objects to Glacier to save money.
# =============================================================================

# Force S3 bucket ownership to the account (needed for consistent ACLs/policies)
resource "aws_s3_bucket" "delta_lake" {
  bucket = var.s3_bucket_name

  tags = {
    Name = "${var.project_name}-delta-lake"
  }
}

# Block all public access — Delta Lake data should never be world-readable
resource "aws_s3_bucket_public_access_block" "delta_lake" {
  bucket = aws_s3_bucket.delta_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Turn on versioning so accidental deletes/overwrites can be recovered
resource "aws_s3_bucket_versioning" "delta_lake" {
  bucket = aws_s3_bucket.delta_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt objects at rest with AWS-managed keys (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "delta_lake" {
  bucket = aws_s3_bucket.delta_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# After N days, move objects under archive/ to Glacier (cheap cold storage)
resource "aws_s3_bucket_lifecycle_configuration" "delta_lake" {
  bucket = aws_s3_bucket.delta_lake.id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    filter {
      prefix = "archive/"
    }

    transition {
      days          = var.s3_glacier_transition_days
      storage_class = "GLACIER"
    }
  }

  # Also expire incomplete multipart uploads to avoid orphaned storage charges
  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
