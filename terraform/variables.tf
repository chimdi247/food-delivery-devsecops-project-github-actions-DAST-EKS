# ═══════════════════════════════════════════════════════════════════
# Variables — EKS Auto Mode (no node config needed!)
# ═══════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
  default     = "arumullayaswanth"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "Food-Delivery"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "food-delivery-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.31"
}

# ─────────────────────────────────────────────────────────────────
# Bastion Server
# ─────────────────────────────────────────────────────────────────
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion (t3.medium for SonarQube)"
  type        = string
  default     = "t3.medium"
}
