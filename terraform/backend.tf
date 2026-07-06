# ═══════════════════════════════════════════════════════════════════
# Terraform Backend — S3 + DynamoDB State Locking
# 
# BEFORE FIRST RUN:
# 1. Create S3 bucket manually (Step 1 in README)
# 2. Create DynamoDB table manually (Step 2 in README)
# 3. Then run: terraform init
# ═══════════════════════════════════════════════════════════════════

terraform {
  backend "s3" {
    bucket         = "food-delivery-terraform-state-0001"
    key            = "production/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "food-delivery-terraform-state-lock"
  }
}
