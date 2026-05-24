resource "aws_kms_key" "ssm" {
  description             = "${var.project_name} SSM Parameter Store encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-ssm-kms"
  }
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/${var.project_name}-ssm"
  target_key_id = aws_kms_key.ssm.key_id
}
