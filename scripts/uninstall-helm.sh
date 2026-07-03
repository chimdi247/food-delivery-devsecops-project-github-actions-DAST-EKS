#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# uninstall-helm.sh
# Uninstalls all Helm releases and cleans up the EKS cluster
#
# Usage: bash uninstall-helm.sh [--all | --component COMPONENT]
# Components: external-secrets, falco, sonarqube, all
# ═══════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

COMPONENT="${1:-all}"

echo "=========================================="
echo "  HELM UNINSTALL — Food Delivery"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────────────────────────
# Uninstall External Secrets Operator
# ─────────────────────────────────────────────────────────────────
uninstall_external_secrets() {
  info "Uninstalling External Secrets Operator..."

  # Delete ExternalSecrets first
  kubectl delete externalsecret --all -n food-delivery 2>/dev/null || true
  kubectl delete secretstore --all -n food-delivery 2>/dev/null || true

  # Uninstall Helm release
  helm uninstall external-secrets -n external-secrets 2>/dev/null || warn "external-secrets release not found"

  # Delete namespace
  kubectl delete namespace external-secrets --ignore-not-found

  # Delete IRSA resources
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
  if [ -n "$AWS_ACCOUNT_ID" ]; then
    aws iam detach-role-policy \
      --role-name food-delivery-eso-role \
      --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/food-delivery-eso-policy" 2>/dev/null || true
    aws iam delete-role --role-name food-delivery-eso-role 2>/dev/null || true
    aws iam delete-policy \
      --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/food-delivery-eso-policy" 2>/dev/null || true
  fi

  info "External Secrets Operator uninstalled ✅"
}

# ─────────────────────────────────────────────────────────────────
# Uninstall Falco
# ─────────────────────────────────────────────────────────────────
uninstall_falco() {
  info "Uninstalling Falco..."

  helm uninstall falco -n falco 2>/dev/null || warn "falco release not found"
  kubectl delete namespace falco --ignore-not-found

  info "Falco uninstalled ✅"
}

# ─────────────────────────────────────────────────────────────────
# Stop SonarQube (Docker)
# ─────────────────────────────────────────────────────────────────
uninstall_sonarqube() {
  info "Stopping SonarQube..."

  docker stop sonarqube 2>/dev/null || true
  docker rm sonarqube 2>/dev/null || true

  info "SonarQube stopped ✅"
  warn "Docker volumes preserved (sonarqube_data, sonarqube_logs, sonarqube_extensions)"
  warn "To delete volumes: docker volume rm sonarqube_data sonarqube_logs sonarqube_extensions"
}

# ─────────────────────────────────────────────────────────────────
# Uninstall application from EKS
# ─────────────────────────────────────────────────────────────────
uninstall_app() {
  info "Removing Food Delivery application from EKS..."

  kubectl delete -f k8s/ingress.yaml 2>/dev/null || true
  kubectl delete -f k8s/admin-deployment.yaml 2>/dev/null || true
  kubectl delete -f k8s/admin-service.yaml 2>/dev/null || true
  kubectl delete -f k8s/frontend-deployment.yaml 2>/dev/null || true
  kubectl delete -f k8s/frontend-service.yaml 2>/dev/null || true
  kubectl delete -f k8s/backend-deployment.yaml 2>/dev/null || true
  kubectl delete -f k8s/backend-service.yaml 2>/dev/null || true
  kubectl delete -f k8s/networkpolicy.yaml 2>/dev/null || true
  kubectl delete secret food-delivery-secrets -n food-delivery 2>/dev/null || true

  info "Application removed from EKS ✅"
}

# ─────────────────────────────────────────────────────────────────
# Clean up Helm repos
# ─────────────────────────────────────────────────────────────────
cleanup_helm_repos() {
  info "Removing Helm repos..."

  helm repo remove autoscaler 2>/dev/null || true
  helm repo remove external-secrets 2>/dev/null || true
  helm repo remove falcosecurity 2>/dev/null || true
  helm repo remove ingress-nginx 2>/dev/null || true

  info "Helm repos removed ✅"
}

# ─────────────────────────────────────────────────────────────────
# Execute based on argument
# ─────────────────────────────────────────────────────────────────
case "$COMPONENT" in
  external-secrets)
    uninstall_external_secrets
    ;;
  falco)
    uninstall_falco
    ;;
  sonarqube)
    uninstall_sonarqube
    ;;
  app)
    uninstall_app
    ;;
  all|--all)
    warn "Uninstalling ALL components..."
    echo ""
    read -p "Are you sure? This will remove everything. (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Cancelled."
      exit 0
    fi
    echo ""
    uninstall_app
    uninstall_external_secrets
    uninstall_falco
    uninstall_sonarqube
    cleanup_helm_repos
    ;;
  *)
    echo "Usage: bash uninstall-helm.sh [COMPONENT]"
    echo ""
    echo "Components:"
    echo "  external-secrets  — Remove External Secrets Operator"
    echo "  falco             — Remove Falco runtime security"
    echo "  sonarqube         — Stop SonarQube container"
    echo "  app               — Remove app from EKS"
    echo "  all               — Remove EVERYTHING (asks confirmation)"
    echo ""
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "  ✅ UNINSTALL COMPLETE"
echo "=========================================="
echo ""
info "Remaining Helm releases:"
helm list -A 2>/dev/null || echo "  (none)"
echo ""
