# ═══════════════════════════════════════════════════════════════════
# Terraform Backend — S3 + DynamoDB State Locking
# 
# Backend config is passed dynamically via GitHub Actions using:
#   terraform init -backend-config="bucket=..." -backend-config="region=..." ...
# This avoids hardcoding values so anyone can reuse this code.
# ═══════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    key     = "production/terraform.tfstate"
    encrypt = true
  }
}
