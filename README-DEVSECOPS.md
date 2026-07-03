# Food Delivery — End-to-End DevSecOps Deployment Guide

## Domain: `tagent.cfd` | Branch: `master`

---

## Architecture

![DevSecOps Architecture](Architecture/devsecops%20project%20Architecture.jpg)

---

## What This Project Does

When you push code → GitHub Actions runs **10 security stages** → deploys to **AWS EKS** → app is live at `https://tagent.cfd`

When you click **destroy** → everything is deleted → your AWS bill becomes **$0**

---

## What Gets Created When You Click "Apply"

| # | Resource | Purpose | Cost/Day |
|---|----------|---------|----------|
| 1 | VPC | Network for everything | $0 |
| 2 | 2 Public Subnets | For bastion + load balancer | $0 |
| 3 | 2 Private Subnets | For EKS pods | $0 |
| 4 | Internet Gateway | Internet access for public subnets | $0 |
| 5 | NAT Gateway | Internet access for private subnets | ~$1.08 |
| 6 | Elastic IP | Static IP for bastion | ~$0.12 |
| 7 | EKS Cluster (Auto Mode) | Kubernetes — runs your app | ~$2.40 |
| 8 | Bastion EC2 (t3.medium) | SonarQube + kubectl access | ~$1.00 |
| 9 | 3 ECR Repositories | Stores Docker images | $0 |
| 10 | AWS Secrets Manager (4 secrets) | Stores all passwords | ~$0.05 |
| 11 | KMS Key | Encrypts EKS secrets | ~$0.03 |
| 12 | Security Groups | Firewall rules | $0 |
| 13 | IAM Policies | Permissions | $0 |
| **Total** | | | **~$5-10/day** |

---

## What Gets Deleted When You Click "Destroy"

**EVERYTHING above** → deleted completely → bill = $0

Things that stay (cost $0):
- S3 bucket (terraform state file)
- DynamoDB table (state lock)
- OIDC provider + IAM role
- ACM certificate
- Route53 hosted zone ($0.50/month)

---

## Step-by-Step Deployment (Don't Skip Any Step!)

---

### PART 1: AWS Console Setup (Do This Once, Never Again)

---

#### Step 1: Login to AWS Console

1. Go to https://console.aws.amazon.com
2. Login with your AWS account
3. Make sure you're in **ap-south-1 (Mumbai)** region (top-right corner)

---

#### Step 2: Create S3 Bucket (Terraform State Storage)

**Why:** Terraform saves what it created in this bucket. Without it, Terraform forgets everything.

1. Search **"S3"** in AWS Console search bar → Click it
2. Click **"Create bucket"**
3. Fill in:
   - Bucket name: `food-delivery-terraform-state-0001` (if taken, add random numbers)
   - Region: **Asia Pacific (Mumbai) ap-south-1**
4. Scroll down → **Bucket Versioning** → Click **Enable**
5. Scroll down → **Default encryption** → Select **SSE-S3 (AES-256)**
6. Leave "Block all public access" **checked** ✅
7. Click **"Create bucket"**

✅ Done! Remember the bucket name.

---

#### Step 3: Create DynamoDB Table (State Lock)

**Why:** Prevents two people from running Terraform at the same time (would corrupt state).

1. Search **"DynamoDB"** in AWS Console → Click it
2. Click **"Create table"**
3. Fill in:
   - Table name: `terraform-state-lock`
   - Partition key: `LockID` (type: **String**)
4. Leave everything else as default
5. Click **"Create table"**

✅ Done!

---

#### Step 4: Create OIDC Identity Provider (GitHub Trust)

**Why:** This tells AWS "I trust GitHub. When GitHub Actions says it's from my repo, give it access." No passwords stored anywhere.

1. Search **"IAM"** in AWS Console → Click it
2. Left sidebar → Click **"Identity providers"**
3. Click **"Add provider"**
4. Fill in:
   - Provider type: **OpenID Connect**
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Click **"Get thumbprint"**
   - Audience: `sts.amazonaws.com`
5. Click **"Add provider"**

✅ Done!

---

#### Step 5: Create IAM Role for GitHub Actions

**Why:** This role has permissions to create/delete AWS resources. GitHub Actions assumes this role via OIDC.

1. Go to **IAM** → Left sidebar → **"Roles"** → Click **"Create role"**
2. Select **"Web identity"**
3. Fill in:
   - Identity provider: `token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
4. Click **"Next"**
5. Search and check **`AdministratorAccess`** (for demo — use custom policy in real production)
6. Click **"Next"**
7. Role name: `GitHubActions-Terraform-Role`
8. Click **"Create role"**

**Now edit the trust policy:**

9. Go to **IAM → Roles** → Click on `GitHubActions-Terraform-Role`
10. Click **"Trust relationships"** tab → Click **"Edit trust policy"**
11. Replace everything with this (change `YOUR_ACCOUNT_ID` to your 12-digit AWS account ID):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:arumullayaswanth/Food-Delivery:*"
        }
      }
    }
  ]
}
```

12. Click **"Update policy"**
13. Go back to the role → Copy the **ARN** at the top. It looks like:
    ```
    arn:aws:iam::123456789012:role/GitHubActions-Terraform-Role
    ```
14. **Save this ARN** — you need it in Step 8.

✅ Done!

---

#### Step 6: Create ACM Certificate (HTTPS for tagent.cfd)

**Why:** So your website has HTTPS (the lock icon). ALB uses this certificate.

1. Search **"Certificate Manager"** in AWS Console → Click it
2. Click **"Request a certificate"**
3. Select **"Request a public certificate"** → Click **"Next"**
4. Domain names:
   - Add: `tagent.cfd`
   - Click **"Add another name to this certificate"**
   - Add: `*.tagent.cfd`
5. Validation method: **DNS validation**
6. Click **"Request"**
7. You'll see the certificate with status "Pending validation"
8. Click on the certificate → Click **"Create records in Route 53"** (if you've already created the hosted zone in Step 7)
   - OR: Copy the CNAME records and add them to your DNS manually
9. Wait 5-30 minutes → Status changes to **"Issued"** ✅

✅ Done!

---

#### Step 7: Create Route53 Hosted Zone (DNS for tagent.cfd)

**Why:** Route53 manages DNS records that point `tagent.cfd` to your app.

1. Search **"Route 53"** in AWS Console → Click it
2. Click **"Hosted zones"** → Click **"Create hosted zone"**
3. Fill in:
   - Domain name: `tagent.cfd`
   - Type: **Public hosted zone**
4. Click **"Create hosted zone"**
5. You'll see **4 NS records** (nameservers). They look like:
   ```
   ns-123.awsdns-45.com
   ns-678.awsdns-90.net
   ns-111.awsdns-22.org
   ns-333.awsdns-44.co.uk
   ```
6. **Go to your domain registrar** (where you bought `tagent.cfd`) → Update nameservers to these 4 values
7. Wait 5-30 minutes for DNS propagation

**Now validate the ACM certificate (if not done in Step 6):**
8. Go back to Certificate Manager → Click on your certificate
9. Click **"Create records in Route 53"** → Click **"Create records"**
10. Wait for status: **Issued** ✅

✅ Done!

---

### PART 2: GitHub Setup

---

#### Step 8: Add GitHub Variables

**Why:** The pipeline reads these values at runtime. Nothing is hardcoded in code.

1. Go to your GitHub repo: `github.com/arumullayaswanth/Food-Delivery`
2. Click **Settings** (tab at top)
3. Left sidebar → **Secrets and variables** → Click **"Actions"**
4. Click the **"Variables"** tab (NOT Secrets!)
5. Click **"New repository variable"** for EACH of these:

| Variable Name | What To Put | Example |
|---|---|---|
| `AWS_REGION` | Your AWS region | `ap-south-1` |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID | `123456789012` |
| `AWS_ROLE_ARN` | The role ARN from Step 5 | `arn:aws:iam::123456789012:role/GitHubActions-Terraform-Role` |
| `TF_STATE_BUCKET` | S3 bucket name from Step 2 | `food-delivery-terraform-state-0001` |
| `TF_LOCK_TABLE` | DynamoDB table from Step 3 | `terraform-state-lock` |
| `EKS_CLUSTER_NAME` | Cluster name | `food-delivery-cluster` |
| `APP_URL` | Your domain | `tagent.cfd` |

**That's it! No GitHub Secrets needed. All sensitive values come from AWS Secrets Manager.**

✅ Done!

---

### PART 3: Deploy Infrastructure (One Click)

---

#### Step 9: Push Code to GitHub

```bash
cd Food-Delivery
git add .
git commit -m "feat: production devsecops pipeline"
git push origin master
```

---

#### Step 10: Create Infrastructure (Click Apply)

1. Go to your GitHub repo → Click **"Actions"** tab
2. Left sidebar → Click **"EKS Terraform"**
3. Click **"Run workflow"** (right side)
4. Select: **`apply`**
5. Click **"Run workflow"** (green button)
6. **Wait ~15-20 minutes** (EKS cluster takes time)
7. When it's green ✅ → Click on the run → Click **"Summary"** tab
8. You'll see everything that was created, the cost estimate, and connection commands

✅ Infrastructure is live!

---

### PART 4: Setup Bastion Server

---

#### Step 11: Connect to Bastion (SSM — No SSH Key Needed)

```bash
# Find bastion instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=food-delivery-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text --region ap-south-1)

# Connect (opens a shell in your terminal)
aws ssm start-session --target $INSTANCE_ID --region ap-south-1
```

**If SSM doesn't work**, wait 5 minutes for the instance to finish booting.

---

#### Step 12: Run tool.sh (If Not Already Run by User Data)

Inside the bastion session:

```bash
sudo su - ec2-user
sudo bash /home/ec2-user/scripts/tool.sh
```

This installs: kubectl, eksctl, Helm, AWS CLI, Docker, SonarQube

---

#### Step 13: Connect to EKS from Bastion

```bash
aws eks update-kubeconfig --name food-delivery-cluster --region ap-south-1
kubectl get nodes
```

**With EKS Auto Mode**: You'll see no nodes yet. Nodes appear when you deploy pods.

---

#### Step 14: Setup SonarQube

1. Get bastion public IP:
```bash
curl http://169.254.169.254/latest/meta-data/public-ipv4
```

2. Open in browser: `http://<BASTION_IP>:9000`
3. Login: `admin` / `admin`
4. It asks you to change password → change it
5. Click **"Create project manually"**
   - Project display name: `food-delivery`
   - Project key: `food-delivery`
6. Click **"Locally"**
7. Generate a token → **Copy the token** (looks like `squ_abc123...`)
8. Now store it in AWS Secrets Manager:

```bash
aws secretsmanager put-secret-value \
  --secret-id food-delivery/pipeline \
  --region ap-south-1 \
  --secret-string "{\"SONAR_TOKEN\":\"squ_YOUR_TOKEN_HERE\",\"SONAR_HOST_URL\":\"http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000\"}"
```

✅ SonarQube ready! The pipeline will fetch the token from Secrets Manager automatically.

---

#### Step 15: Install External Secrets Operator

This auto-syncs secrets from AWS Secrets Manager → Kubernetes. No manual `kubectl create secret` needed.

```bash
bash /home/ec2-user/scripts/install-external-secrets.sh
```

---

#### Step 16: Put Real Secrets in AWS Secrets Manager

```bash
aws secretsmanager put-secret-value \
  --secret-id food-delivery/app-secrets \
  --region ap-south-1 \
  --secret-string '{
    "MONGODB_URI": "mongodb+srv://YOUR_USER:YOUR_PASS@cluster.mongodb.net/food-delivery",
    "JWT_SECRET": "your-super-strong-jwt-secret-change-this",
    "STRIPE_SECRET_KEY": "sk_live_your-real-stripe-key"
  }'
```

External Secrets Operator syncs this to Kubernetes automatically every 1 hour.

**To force immediate sync:**
```bash
kubectl annotate externalsecret food-delivery-secrets -n food-delivery force-sync=$(date +%s) --overwrite
```

---

#### Step 17: Install Falco (Runtime Security)

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=ebpf \
  --set falcosidekick.enabled=true
```

Verify:
```bash
kubectl get pods -n falco
```

---

### PART 5: Deploy the Application

---

#### Step 18: Push Any Code Change → Pipeline Runs Automatically

```bash
# Make any small change (or just push)
git add .
git commit -m "trigger pipeline"
git push origin master
```

Go to **GitHub → Actions** → Watch the **"DevSecOps Pipeline"** run all 10 stages:

```
Stage 1:  Gitleaks (secret scanning)        ✅
Stage 2:  SonarQube (code analysis)         ✅
Stage 3:  Trivy (dependency scan)           ✅
Stage 4:  Docker build (distroless images)  ✅
Stage 5:  Trivy (image scan)               ✅
Stage 6:  Checkov (IaC scan)               ✅
Stage 7:  Push to ECR (OIDC)               ✅
Stage 8:  Deploy to EKS (secrets from SM)  ✅
Stage 9:  OWASP ZAP (DAST)                ✅
Stage 10: Falco validation                  ✅
```

---

#### Step 19: Add DNS Records (Point Domain to ALB)

After the pipeline deploys successfully:

1. Get the ALB URL:
```bash
kubectl get ingress -n food-delivery
```
Copy the ADDRESS (looks like: `k8s-fooddeli-xxx.ap-south-1.elb.amazonaws.com`)

2. Go to **AWS Console → Route 53 → tagent.cfd hosted zone**

3. Create record:
   - Record name: (leave empty — this is for `tagent.cfd`)
   - Record type: **A**
   - Toggle **"Alias"** ON
   - Route traffic to: **"Alias to Application and Classic Load Balancer"**
   - Region: **Asia Pacific (Mumbai)**
   - Select your ALB from dropdown
   - Click **"Create records"**

4. Create another record:
   - Record name: `admin`
   - Record type: **A**
   - Toggle **"Alias"** ON
   - Same ALB as above
   - Click **"Create records"**

5. Wait 2-5 minutes → Open browser:
   - `https://tagent.cfd` → Frontend ✅
   - `https://tagent.cfd/api/food` → Backend API ✅
   - `https://admin.tagent.cfd` → Admin Panel ✅

✅ **YOUR APP IS LIVE IN PRODUCTION!** 🎉

---

### PART 6: Destroy Everything (Bill → $0)

---

#### Step 20: One-Click Destroy

1. Go to **GitHub → Actions** → Left sidebar → **"EKS Terraform"**
2. Click **"Run workflow"**
3. Select: **`destroy`**
4. In "confirm_destroy" field: type **`yes`**
5. Click **"Run workflow"**
6. Wait ~10-15 minutes
7. Check the **Summary** tab — it shows a table verifying everything is deleted

**What happens during destroy:**
- Uninstalls all Helm releases (Falco, External Secrets)
- Deletes all Kubernetes services/ingresses (removes ALBs)
- Deletes all PVCs (removes EBS volumes)
- Runs `terraform destroy` (removes all infrastructure)
- Post-destroy cleanup: catches any orphaned LBs, EBS volumes, EIPs, NAT gateways, snapshots
- Final verification: checks if anything billable remains

**After destroy, your bill = $0** (Route53 zone = $0.50/month, everything else gone)

---

#### Step 21: Recreate Later (When You Need It Again)

1. Go to **GitHub → Actions → EKS Terraform**
2. Run workflow → Select **`apply`**
3. Wait 15-20 minutes
4. Everything comes back (repeat Steps 11-19)

---

## Quick Reference

### Connect to Bastion
```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=food-delivery-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text --region ap-south-1)
aws ssm start-session --target $INSTANCE_ID --region ap-south-1
```

### Connect to EKS
```bash
aws eks update-kubeconfig --name food-delivery-cluster --region ap-south-1
kubectl get pods -n food-delivery
```

### Check App Status
```bash
kubectl get pods -n food-delivery
kubectl get svc -n food-delivery
kubectl get ingress -n food-delivery
```

### View Logs
```bash
kubectl logs -f deployment/food-delivery-backend -n food-delivery
kubectl logs -f deployment/food-delivery-frontend -n food-delivery
```

### Force Secret Sync
```bash
kubectl annotate externalsecret food-delivery-secrets -n food-delivery force-sync=$(date +%s) --overwrite
```

---

## File Structure

```
Food-Delivery/
├── .github/workflows/
│   ├── terraform-infra.yml        ← One-click apply/destroy (OIDC)
│   ├── devsecops-pipeline.yml     ← 10-stage security pipeline
│   └── dependabot.yml             ← Auto-update dependencies
├── terraform/
│   ├── provider.tf + backend.tf   ← AWS + S3 state
│   ├── vpc.tf                     ← Network
│   ├── eks.tf                     ← EKS Auto Mode
│   ├── ecr.tf                     ← Image registries
│   ├── bastion.tf                 ← Jump server + SonarQube
│   ├── secrets-manager.tf         ← All secrets
│   ├── oidc.tf                    ← GitHub → AWS trust
│   ├── outputs.tf                 ← Shows what was created
│   └── variables.tf               ← Configuration
├── k8s/
│   ├── namespace.yaml             ← PSS restricted
│   ├── *-deployment.yaml          ← Hardened pods (3 apps)
│   ├── *-service.yaml             ← ClusterIP services
│   ├── ingress.yaml               ← ALB + HTTPS (tagent.cfd)
│   ├── networkpolicy.yaml         ← Zero-trust networking
│   └── storageclass.yaml          ← EBS gp3
├── scripts/
│   ├── tool.sh                    ← Bastion setup
│   ├── install-external-secrets.sh ← Auto-sync secrets
│   └── uninstall-helm.sh          ← Cleanup
├── backend/Dockerfile             ← Distroless Node.js
├── frontend/Dockerfile            ← Distroless nginx
├── admin/Dockerfile               ← Distroless nginx
├── .gitleaks.toml                 ← Secret scanning rules
├── sonar-project.properties       ← SonarQube config
├── CODEOWNERS                     ← Security team reviews
└── README-DEVSECOPS.md            ← This file
```

---

## Security Summary

| What | How |
|------|-----|
| No AWS keys in GitHub | OIDC authentication |
| No secrets in code | AWS Secrets Manager |
| No SSH keys | SSM Session Manager |
| No root containers | Distroless images + USER 65534 |
| No open ports | Network Policies (deny-all default) |
| No manual node management | EKS Auto Mode |
| No unscanned code | SonarQube SAST + Trivy SCA |
| No vulnerable images | Trivy image scan (fail on HIGH/CRITICAL) |
| No insecure k8s config | Checkov + PSS Restricted |
| No runtime threats | Falco eBPF monitoring |
| No unpatched deps | Dependabot daily checks |
| HTTPS everywhere | ACM certificate + ALB |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| SSM won't connect | Wait 5 min for instance to boot. Check IAM role has `AmazonSSMManagedInstanceCore` |
| SonarQube not loading | SSH via SSM → `docker logs sonarqube` → check if container is running |
| Pipeline fails at SonarQube | Check Secrets Manager has correct SONAR_TOKEN + SONAR_HOST_URL |
| EKS nodes not appearing | Normal with Auto Mode — nodes appear only when pods are scheduled |
| Destroy fails | It retries automatically. Orphaned ENIs/SGs are cleaned up in post-destroy steps |
| ALB not created | Check ingress has `ingressClassName: alb` and EKS Auto Mode has networking enabled |
| HTTPS not working | Check ACM certificate status is "Issued" and Route53 CNAME records exist |
| Secrets not syncing | Run `kubectl describe externalsecret -n food-delivery` to check errors |
