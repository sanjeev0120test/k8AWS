resource "random_password" "mongo" {
  length  = 24
  special = false
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

resource "aws_ssm_parameter" "mongo_password" {
  name        = "/${var.project_name}/mongo-password"
  description = "MongoDB root password"
  type        = "SecureString"
  value       = random_password.mongo.result
  key_id      = aws_kms_key.ssm.arn

  tags = {
    Name = "${var.project_name}-mongo-password"
  }
}

resource "aws_ssm_parameter" "mongo_username" {
  name        = "/${var.project_name}/mongo-username"
  description = "MongoDB root username"
  type        = "String"
  value       = "admin"

  tags = {
    Name = "${var.project_name}-mongo-username"
  }
}

resource "aws_ssm_parameter" "grafana_password" {
  name        = "/${var.project_name}/grafana-admin-password"
  description = "Grafana admin password"
  type        = "SecureString"
  value       = random_password.grafana.result
  key_id      = aws_kms_key.ssm.arn

  tags = {
    Name = "${var.project_name}-grafana-password"
  }
}

resource "aws_ssm_parameter" "grafana_username" {
  name        = "/${var.project_name}/grafana-admin-username"
  description = "Grafana admin username"
  type        = "String"
  value       = "admin"

  tags = {
    Name = "${var.project_name}-grafana-username"
  }
}
