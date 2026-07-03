# ═══════════════════════════════════════════════════════════════════
# GitHub OIDC — CREATED MANUALLY (Steps 3-4 in README)
#
# The OIDC provider and IAM role are created manually in AWS Console
# BEFORE running Terraform. This file only references the existing
# role for use in other Terraform resources (EKS access, etc.)
#
# Manual steps already done:
# 1. Created OIDC provider: token.actions.githubusercontent.com
# 2. Created IAM role: GitHubActions-Terraform-Role
# 3. Added role ARN to GitHub Variables: AWS_ROLE_ARN
# ═══════════════════════════════════════════════════════════════════

# Reference the manually created GitHub Actions role
data "aws_iam_role" "github_actions" {
  name = "GitHubActions-Terraform-Role"
}

# ─────────────────────────────────────────────────────────────────
# Additional policies for the existing GitHub Actions role
# (ECR push, EKS deploy, Secrets Manager read)
# ─────────────────────────────────────────────────────────────────

# Policy: ECR push/pull access
resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "ecr-access"
  role = data.aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = [
          aws_ecr_repository.backend.arn,
          aws_ecr_repository.frontend.arn,
          aws_ecr_repository.admin.arn
        ]
      }
    ]
  })
}

# Policy: EKS access for deployment
resource "aws_iam_role_policy" "github_actions_eks" {
  name = "eks-access"
  role = data.aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = aws_eks_cluster.main.arn
      }
    ]
  })
}

# Policy: Secrets Manager access (read pipeline secrets)
resource "aws_iam_role_policy" "github_actions_secrets" {
  name = "secrets-manager-access"
  role = data.aws_iam_role.github_actions.id

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

# Policy: ACM read (to fetch certificate ARN for tagent.cfd)
resource "aws_iam_role_policy" "github_actions_acm" {
  name = "acm-read-access"
  role = data.aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm:ListCertificates",
          "acm:DescribeCertificate"
        ]
        Resource = "*"
      }
    ]
  })
}
