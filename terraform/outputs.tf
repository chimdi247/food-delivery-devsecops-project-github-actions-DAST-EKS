# ═══════════════════════════════════════════════════════════════════
# Outputs — Values you need for GitHub Variables
# ═══════════════════════════════════════════════════════════════════

output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions (set as AWS_ROLE_ARN in GitHub Vars)"
  value       = data.aws_iam_role.github_actions.arn
}

output "ecr_registry" {
  description = "ECR Registry URL"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_backend_repo" {
  description = "ECR Backend Repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repo" {
  description = "ECR Frontend Repository URL"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_admin_repo" {
  description = "ECR Admin Repository URL"
  value       = aws_ecr_repository.admin.repository_url
}

output "eks_cluster_name" {
  description = "EKS Cluster Name (set as EKS_CLUSTER_NAME in GitHub Vars)"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API Endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_auto_mode" {
  description = "EKS Auto Mode status"
  value       = "ENABLED — AWS manages compute, networking, and storage automatically"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "bastion_public_ip" {
  description = "Bastion server public IP (SSH + SonarQube access)"
  value       = aws_eip.bastion.public_ip
}

output "sonarqube_url" {
  description = "SonarQube URL (login: admin/admin — change on first login!)"
  value       = "http://${aws_eip.bastion.public_ip}:9000"
}

output "secrets_manager_app" {
  description = "AWS Secrets Manager — Application secrets ARN"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secrets_manager_sonarqube" {
  description = "AWS Secrets Manager — SonarQube secrets ARN"
  value       = aws_secretsmanager_secret.sonarqube.arn
}

output "secrets_manager_pipeline" {
  description = "AWS Secrets Manager — Pipeline secrets ARN"
  value       = aws_secretsmanager_secret.pipeline.arn
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# ═══════════════════════════════════════════════════════════════════
# GitHub Variables Summary (copy these to your repo settings)
# ═══════════════════════════════════════════════════════════════════
output "github_variables_summary" {
  description = "Variables to set in GitHub repo Settings > Secrets and Variables > Actions"
  value       = <<-EOT

    ┌─────────────────────────────────────────────────────────────────┐
    │          SET THESE IN GITHUB REPO → SETTINGS → VARIABLES        │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                   │
    │  AWS_ACCOUNT_ID   = ${data.aws_caller_identity.current.account_id}
    │  AWS_ROLE_ARN     = ${data.aws_iam_role.github_actions.arn}
    │  AWS_REGION       = ${var.aws_region}
    │  EKS_CLUSTER_NAME = ${aws_eks_cluster.main.name}
    │  APP_URL          = <your-app-domain-or-load-balancer-url>
    │                                                                   │
    ├─────────────────────────────────────────────────────────────────┤
    │          SET THESE IN GITHUB REPO → SETTINGS → SECRETS          │
    ├─────────────────────────────────────────────────────────────────┤
    │                                                                   │
    │  SONAR_TOKEN      = <from sonarcloud.io>                         │
    │  SONAR_HOST_URL   = https://sonarcloud.io                        │
    │                                                                   │
    └─────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────────────┐
    │                    EKS AUTO MODE — ENABLED                        │
    ├─────────────────────────────────────────────────────────────────┤
    │  ✓ Compute: AWS auto-scales nodes (no node groups)               │
    │  ✓ Networking: VPC CNI + ALB/NLB managed by AWS                  │
    │  ✓ Storage: EBS CSI driver managed by AWS                        │
    │  ✓ Node Pools: general-purpose + system                          │
    └─────────────────────────────────────────────────────────────────┘

  EOT
}
