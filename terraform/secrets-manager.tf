# ═══════════════════════════════════════════════════════════════════
# AWS Secrets Manager — ALL secrets stored here (ZERO hardcoding)
# 
# Secrets are created with placeholder values.
# Update them via AWS Console or CLI after first deploy.
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────
# Application Secrets (used by EKS pods via External Secrets Operator)
# ─────────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "food-delivery/app-secrets"
  description             = "Food Delivery application secrets (MongoDB, JWT, Stripe)"
  recovery_window_in_days = 0

  tags = {
    Name = "food-delivery-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    MONGODB_URI       = "CHANGE_ME"
    JWT_SECRET        = "CHANGE_ME"
    STRIPE_SECRET_KEY = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string] # Don't overwrite after manual update
  }
}

# ─────────────────────────────────────────────────────────────────
# SonarQube Secrets (used by GitHub Actions pipeline)
# ─────────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "sonarqube" {
  name                    = "food-delivery/sonarqube"
  description             = "SonarQube server credentials"
  recovery_window_in_days = 0

  tags = {
    Name = "food-delivery-sonarqube"
  }
}

resource "aws_secretsmanager_secret_version" "sonarqube" {
  secret_id = aws_secretsmanager_secret.sonarqube.id
  secret_string = jsonencode({
    SONAR_TOKEN    = "CHANGE_ME"
    SONAR_HOST_URL = "http://${aws_eip.bastion.public_ip}:9000"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ─────────────────────────────────────────────────────────────────
# Database Credentials (for production MongoDB Atlas or DocumentDB)
# ─────────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "database" {
  name                    = "food-delivery/database"
  description             = "Database connection credentials"
  recovery_window_in_days = 0

  tags = {
    Name = "food-delivery-database"
  }
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    DB_HOST     = "CHANGE_ME"
    DB_USERNAME = "CHANGE_ME"
    DB_PASSWORD = "CHANGE_ME"
    DB_NAME     = "food-delivery"
    DB_PORT     = "27017"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ─────────────────────────────────────────────────────────────────
# GitHub Actions Pipeline Secrets (read by pipeline via OIDC)
# ─────────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "pipeline" {
  name                    = "food-delivery/pipeline"
  description             = "CI/CD pipeline configuration secrets"
  recovery_window_in_days = 0

  tags = {
    Name = "food-delivery-pipeline"
  }
}

resource "aws_secretsmanager_secret_version" "pipeline" {
  secret_id = aws_secretsmanager_secret.pipeline.id
  secret_string = jsonencode({
    SONAR_TOKEN    = "CHANGE_ME"
    SONAR_HOST_URL = "http://${aws_eip.bastion.public_ip}:9000"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ─────────────────────────────────────────────────────────────────
# IAM Policy: Allow EKS pods (via IRSA) to read app secrets
# ─────────────────────────────────────────────────────────────────
resource "aws_iam_policy" "eks_secrets_access" {
  name        = "food-delivery-eks-secrets-access"
  description = "Allow EKS pods to read application secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.app_secrets.arn,
          aws_secretsmanager_secret.database.arn
        ]
      }
    ]
  })
}
