output "instance_id" {
  description = "EC2 instance ID for SSM sessions"
  value       = aws_instance.k8s_node.id
}

output "public_ip" {
  description = "Public IP for curl tests against NodePort/Ingress"
  value       = aws_instance.k8s_node.public_ip
}

output "private_ip" {
  description = "Private IP used by kubeadm"
  value       = aws_instance.k8s_node.private_ip
}

output "vpc_id" {
  description = "Custom VPC ID"
  value       = aws_vpc.main.id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "project_name" {
  description = "Project tag name"
  value       = var.project_name
}

output "estimated_hourly_cost_usd" {
  description = "Approximate on-demand hourly cost (deducted from free-tier credits)"
  value       = "0.096"
}

output "ssm_session_command" {
  description = "Command to open SSM session (no SSH required)"
  value       = "aws ssm start-session --target ${aws_instance.k8s_node.id} --region ${var.aws_region}"
}

output "velero_bucket_name" {
  description = "S3 bucket for Velero backups"
  value       = var.enable_velero_bucket ? aws_s3_bucket.velero[0].bucket : ""
}

output "grafana_password_ssm_path" {
  description = "SSM path for Grafana admin password (retrieve after deploy)"
  value       = aws_ssm_parameter.grafana_password.name
  sensitive   = true
}

output "mongo_password_ssm_path" {
  description = "SSM path for MongoDB password"
  value       = aws_ssm_parameter.mongo_password.name
  sensitive   = true
}
