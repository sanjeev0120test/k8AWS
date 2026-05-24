data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "k8s_node" {
  name        = "${var.project_name}-k8s-sg"
  description = "Security group for kubeadm node — SSM only, no SSH"
  vpc_id      = aws_vpc.main.id

  # SSM agent needs outbound HTTPS
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API (internal)
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NodePort range for ingress/nginx
  ingress {
    description = "NodePort HTTP ingress"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  # Grafana NodePort
  ingress {
    description = "Grafana NodePort"
    from_port   = 30300
    to_port     = 30300
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  # HTTP via hostNetwork ingress controller
  ingress {
    description = "HTTP ingress controller"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ingress_cidr]
  }

  # Calico BGP (optional)
  ingress {
    description = "Calico BGP"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Node-to-node / kubelet
  ingress {
    description = "Kubelet and inter-node"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-k8s-sg"
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_ssm_read" {
  name = "${var.project_name}-ec2-node-policy"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.ssm.arn
      }
      ], var.enable_velero_bucket ? [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.velero[0].arn,
          "${aws_s3_bucket.velero[0].arn}/*"
        ]
      }
    ] : [])
  })
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "k8s_node" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k8s_node.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.ebs_volume_size
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 3 # pods (ESO, Velero) reach IMDSv2 for instance profile credentials
  }

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = templatefile("${path.module}/user-data/kubeadm-init.sh", {
    aws_region   = var.aws_region
    project_name = var.project_name
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-k8s-node"
  }

  lifecycle {
    precondition {
      condition     = var.aws_region == "us-east-1"
      error_message = "Cost guardrail: region must be us-east-1."
    }
  }
}
