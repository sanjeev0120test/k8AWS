resource "aws_s3_bucket" "velero" {
  count  = var.enable_velero_bucket ? 1 : 0
  bucket = "${lower(var.project_name)}-velero-${data.aws_caller_identity.current.account_id}"

  force_destroy = true

  tags = {
    Name = "${var.project_name}-velero-backups"
  }
}

resource "aws_s3_bucket_versioning" "velero" {
  count  = var.enable_velero_bucket ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  count  = var.enable_velero_bucket ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  count  = var.enable_velero_bucket ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  count  = var.enable_velero_bucket ? 1 : 0
  bucket = aws_s3_bucket.velero[0].id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }

    filter {}
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_user" "velero" {
  count = var.enable_velero_bucket ? 1 : 0
  name  = "${var.project_name}-velero"
}

resource "aws_iam_user_policy" "velero_s3" {
  count = var.enable_velero_bucket ? 1 : 0
  name  = "${var.project_name}-velero-s3"
  user  = aws_iam_user.velero[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.velero[0].arn,
          "${aws_s3_bucket.velero[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_access_key" "velero" {
  count = var.enable_velero_bucket ? 1 : 0
  user  = aws_iam_user.velero[0].name
}

resource "aws_ssm_parameter" "velero_access_key_id" {
  count       = var.enable_velero_bucket ? 1 : 0
  name        = "/${var.project_name}/velero-access-key-id"
  description = "Velero AWS access key ID"
  type        = "SecureString"
  value       = aws_iam_access_key.velero[0].id
}

resource "aws_ssm_parameter" "velero_secret_access_key" {
  count       = var.enable_velero_bucket ? 1 : 0
  name        = "/${var.project_name}/velero-secret-access-key"
  description = "Velero AWS secret access key"
  type        = "SecureString"
  value       = aws_iam_access_key.velero[0].secret
}

resource "aws_ssm_parameter" "velero_bucket" {
  count       = var.enable_velero_bucket ? 1 : 0
  name        = "/${var.project_name}/velero-bucket"
  description = "Velero S3 bucket name"
  type        = "String"
  value       = aws_s3_bucket.velero[0].bucket
}
