# ═══════════════════════════════════════════════════════════════════
# Bastion Server — EC2 Instance
# Purpose: Connect to EKS + Run SonarQube (Docker)
# ═══════════════════════════════════════════════════════════════════

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  name        = "food-delivery-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  # SonarQube UI (port 9000)
  ingress {
    description = "SonarQube UI"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "food-delivery-bastion-sg"
  }
}

# IAM Role for Bastion (to access EKS + Secrets Manager)
resource "aws_iam_role" "bastion" {
  name = "food-delivery-bastion-role"

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

# Bastion can access EKS
resource "aws_iam_role_policy" "bastion_eks" {
  name = "bastion-eks-access"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = aws_eks_cluster.main.arn
      }
    ]
  })
}

# Bastion can read secrets from Secrets Manager
resource "aws_iam_role_policy" "bastion_secrets" {
  name = "bastion-secrets-access"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:food-delivery/*"
      }
    ]
  })
}

# Bastion can pull from ECR (for SonarQube image)
resource "aws_iam_role_policy_attachment" "bastion_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.bastion.name
}

# SSM access (for Session Manager — no SSH key needed)
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

# Instance Profile
resource "aws_iam_instance_profile" "bastion" {
  name = "food-delivery-bastion-profile"
  role = aws_iam_role.bastion.name
}

# Elastic IP for stable public IP
resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name = "food-delivery-bastion-eip"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

# ═══════════════════════════════════════════════════════════════════
# Bastion EC2 Instance
# Installs: Docker, kubectl, AWS CLI, SonarQube (Docker Compose)
# ═══════════════════════════════════════════════════════════════════
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(file("${path.module}/../scripts/tool.sh"))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only (security)
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "food-delivery-bastion"
  }
}

# ═══════════════════════════════════════════════════════════════════
# EKS Access Entry — Allow Bastion to manage the cluster
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.bastion.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.bastion.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
