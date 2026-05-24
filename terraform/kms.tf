data "aws_caller_identity" "kms" {}

resource "aws_kms_key" "ssm" {
  description             = "${var.project_name} SSM Parameter Store encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-ssm-kms"
  }
}

resource "aws_kms_key_policy" "ssm" {
  key_id = aws_kms_key.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.kms.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEc2RoleDecryptForSsm"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2_ssm.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/${var.project_name}-ssm"
  target_key_id = aws_kms_key.ssm.key_id
}