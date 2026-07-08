#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# install-external-secrets-pipeline.sh
# Installs External Secrets Operator on EKS (called from GitHub Actions)
# Syncs secrets from AWS Secrets Manager → Kubernetes Secrets
#
# Required environment variables:
#   CLUSTER_NAME   — EKS cluster name
#   AWS_REGION     — AWS region (e.g., ap-south-1)
# ═══════════════════════════════════════════════════════════════════

NAMESPACE="food-delivery"
ESO_NAMESPACE="external-secrets"
ESO_SERVICE_ACCOUNT="external-secrets"
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-food-delivery-cluster}"

echo "=========================================="
echo "  EXTERNAL SECRETS OPERATOR — Pipeline"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Verify cluster exists and connect
# ─────────────────────────────────────────────────────────────────
echo "Configuring kubectl for cluster: ${CLUSTER_NAME}"

if ! aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "ERROR: Cluster ${CLUSTER_NAME} was not found in region ${AWS_REGION}."
  echo "Clusters currently visible in this account and region:"
  aws eks list-clusters --region "${AWS_REGION}" || true
  exit 1
fi

echo "Waiting for cluster to become ACTIVE..."
aws eks wait cluster-active --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# ─────────────────────────────────────────────────────────────────
# Step 2: Wait for nodes to be ready (EKS Auto Mode spins up nodes on demand)
# ─────────────────────────────────────────────────────────────────
echo "Waiting for nodes to be Ready (EKS Auto Mode may take a few minutes)..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s || {
  echo "WARNING: Nodes not ready yet. Proceeding anyway (Helm will wait for pods)..."
}

# ─────────────────────────────────────────────────────────────────
# Step 3: Install Helm (if not present)
# ─────────────────────────────────────────────────────────────────
if ! command -v helm &> /dev/null; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ─────────────────────────────────────────────────────────────────
# Step 4: Install External Secrets Operator via Helm
# ─────────────────────────────────────────────────────────────────
echo "Adding External Secrets Helm repo..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

echo "Installing External Secrets Operator..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "${ESO_NAMESPACE}" \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.create=true \
  --set serviceAccount.name="${ESO_SERVICE_ACCOUNT}"

echo "Waiting for External Secrets deployment to be available..."
kubectl rollout status deployment/external-secrets \
  -n "${ESO_NAMESPACE}" --timeout=300s

echo "Verifying External Secrets installation..."
kubectl get deployment -n "${ESO_NAMESPACE}" external-secrets
kubectl get pods -n "${ESO_NAMESPACE}"
kubectl get crd externalsecrets.external-secrets.io

echo ""
echo "✅ External Secrets Operator installed successfully."
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 5: Setup IRSA (IAM Role for Service Account)
# ─────────────────────────────────────────────────────────────────
echo "Setting up IAM for External Secrets..."

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

echo "  Account: ${AWS_ACCOUNT_ID}"
echo "  OIDC: ${OIDC_PROVIDER}"

# Create IAM policy for Secrets Manager access
cat > /tmp/eso-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:food-delivery/*"
    }
  ]
}
EOF

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/food-delivery-eso-policy"
aws iam create-policy \
  --policy-name food-delivery-eso-policy \
  --policy-document file:///tmp/eso-policy.json 2>/dev/null || \
aws iam create-policy-version \
  --policy-arn ${POLICY_ARN} \
  --policy-document file:///tmp/eso-policy.json \
  --set-as-default 2>/dev/null || true

# Create trust policy for IRSA
cat > /tmp/eso-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:food-delivery-eso-sa",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

ROLE_NAME="food-delivery-eso-role"
aws iam create-role \
  --role-name ${ROLE_NAME} \
  --assume-role-policy-document file:///tmp/eso-trust.json 2>/dev/null || \
aws iam update-assume-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-document file:///tmp/eso-trust.json

aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn ${POLICY_ARN} 2>/dev/null || true

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo "  IAM Role: ${ROLE_ARN}"

# ─────────────────────────────────────────────────────────────────
# Step 6: Create Kubernetes resources
# ─────────────────────────────────────────────────────────────────
echo "Creating Kubernetes resources..."

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Service Account with IRSA annotation
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: food-delivery-eso-sa
  namespace: ${NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF

# SecretStore (connects to AWS Secrets Manager)
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: ${NAMESPACE}
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${AWS_REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: food-delivery-eso-sa
EOF

# ExternalSecret (syncs AWS Secrets Manager → K8s Secret)
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: food-delivery-secrets
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: food-delivery-secrets
    creationPolicy: Owner
  data:
    - secretKey: mongodb-uri
      remoteRef:
        key: food-delivery/app-secrets
        property: MONGODB_URI
    - secretKey: jwt-secret
      remoteRef:
        key: food-delivery/app-secrets
        property: JWT_SECRET
    - secretKey: stripe-secret-key
      remoteRef:
        key: food-delivery/app-secrets
        property: STRIPE_SECRET_KEY
EOF

# ─────────────────────────────────────────────────────────────────
# Step 7: Verify
# ─────────────────────────────────────────────────────────────────
echo "Waiting for secret sync..."
sleep 15

kubectl get externalsecret -n ${NAMESPACE}
kubectl get secret food-delivery-secrets -n ${NAMESPACE} 2>/dev/null || echo "  (secret will sync after real values are added to AWS Secrets Manager)"

echo ""
echo "=========================================="
echo "  ✅ EXTERNAL SECRETS SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Secrets auto-sync from AWS Secrets Manager every 1 hour."
