variable "aws_region" {
  description = "AWS region (must be us-east-1 for this lab)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project tag used for all resources"
  type        = string
  default     = "k8AWS"
}

variable "instance_type" {
  description = "EC2 instance type — must be free-tier eligible m7i-flex.large"
  type        = string
  default     = "m7i-flex.large"

  validation {
    condition     = var.instance_type == "m7i-flex.large"
    error_message = "Cost guardrail: only m7i-flex.large is allowed for this lab."
  }
}

variable "ebs_volume_size" {
  description = "Root EBS volume size in GB (stay within free tier)"
  type        = number
  default     = 20

  validation {
    condition     = var.ebs_volume_size >= 8 && var.ebs_volume_size <= 30
    error_message = "EBS size must be between 8 and 30 GB for free tier budget."
  }
}

variable "vpc_cidr" {
  description = "CIDR for custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ingress_cidr" {
  description = "CIDR allowed to reach NodePort/Ingress — MUST set to your public IP/32"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = var.allowed_ingress_cidr != "0.0.0.0/0" || var.allow_public_ingress
    error_message = "Set allowed_ingress_cidr to YOUR_IP/32 or set allow_public_ingress=true to acknowledge open ingress."
  }
}

variable "allow_public_ingress" {
  description = "Explicit opt-in for 0.0.0.0/0 ingress (not recommended)"
  type        = bool
  default     = false
}

variable "enable_velero_bucket" {
  description = "Create S3 bucket for Velero backups (uses free tier 5GB)"
  type        = bool
  default     = true
}
