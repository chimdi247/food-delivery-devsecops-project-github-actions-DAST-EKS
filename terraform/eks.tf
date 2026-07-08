# ═══════════════════════════════════════════════════════════════════
# Amazon EKS Cluster — AUTO MODE (No node groups to manage!)
# AWS handles: compute scaling, VPC CNI, load balancers, EBS CSI
# ═══════════════════════════════════════════════════════════════════

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "food-delivery-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# Compute role (for Auto Mode managed nodes)
resource "aws_iam_role_policy_attachment" "eks_compute_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Networking role (for Auto Mode VPC CNI + LB controller)
resource "aws_iam_role_policy_attachment" "eks_networking_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Block storage (for Auto Mode EBS CSI)
resource "aws_iam_role_policy_attachment" "eks_block_storage_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Load balancing (for Auto Mode ALB/NLB)
resource "aws_iam_role_policy_attachment" "eks_load_balancing_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Security Group for EKS Cluster
resource "aws_security_group" "eks_cluster" {
  name        = "food-delivery-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "food-delivery-eks-cluster-sg"
  }
}

# KMS Key for EKS secrets encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "food-delivery-eks-kms"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/food-delivery-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ═══════════════════════════════════════════════════════════════════
# EKS Cluster with AUTO MODE ENABLED
# No managed node groups needed. AWS provisions nodes automatically.
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  # Required when EKS Auto Mode is enabled
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # ┌─────────────────────────────────────────────────┐
  # │         EKS AUTO MODE CONFIGURATION              │
  # │  Enables: Compute, Networking, Storage           │
  # │  No node groups, no Karpenter, no CSI drivers    │
  # │  AWS manages everything automatically            │
  # └─────────────────────────────────────────────────┘

  # Auto Mode: Compute (replaces managed node groups + Karpenter)
  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.eks_node.arn
  }

  # Auto Mode: Networking (replaces VPC CNI addon + AWS LB Controller)
  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  # Auto Mode: Storage (replaces EBS CSI driver addon)
  storage_config {
    block_storage {
      enabled = true
    }
  }

  # Envelope encryption for Kubernetes secrets
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  # Enable audit logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_iam_role_policy_attachment.eks_compute_policy,
    aws_iam_role_policy_attachment.eks_networking_policy,
    aws_iam_role_policy_attachment.eks_block_storage_policy,
    aws_iam_role_policy_attachment.eks_load_balancing_policy,
  ]
}

# ═══════════════════════════════════════════════════════════════════
# IAM Role for Auto Mode Nodes (EC2 instances managed by AWS)
# ═══════════════════════════════════════════════════════════════════
resource "aws_iam_role" "eks_node" {
  name = "food-delivery-eks-auto-node-role"

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

resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.eks_node.name
}

# ═══════════════════════════════════════════════════════════════════
# EKS Access Entry — Allow GitHub Actions role to deploy
# ═══════════════════════════════════════════════════════════════════
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_role.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
