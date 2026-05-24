# IAM user for External Secrets Operator (reads SSM from inside cluster)
resource "aws_iam_user" "eso" {
  name = "${var.project_name}-eso-reader"
}

resource "aws_iam_user_policy" "eso_ssm_read" {
  name = "${var.project_name}-eso-ssm-read"
  user = aws_iam_user.eso.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*"
      }
    ]
  })
}

resource "aws_iam_access_key" "eso" {
  user = aws_iam_user.eso.name
}

resource "aws_ssm_parameter" "eso_access_key_id" {
  name        = "/${var.project_name}/eso-access-key-id"
  description = "External Secrets Operator AWS access key ID"
  type        = "SecureString"
  value       = aws_iam_access_key.eso.id
}

resource "aws_ssm_parameter" "eso_secret_access_key" {
  name        = "/${var.project_name}/eso-secret-access-key"
  description = "External Secrets Operator AWS secret access key"
  type        = "SecureString"
  value       = aws_iam_access_key.eso.secret
}
