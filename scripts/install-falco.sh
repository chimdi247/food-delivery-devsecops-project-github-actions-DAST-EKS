#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# install-falco.sh
# Installs Falco Runtime Security on EKS
# Monitors containers for suspicious behavior at runtime
#
# Usage: bash install-falco.sh
# ═══════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

echo "=========================================="
echo "  FALCO — Runtime Security Setup"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Install Helm (if not present)
# ─────────────────────────────────────────────────────────────────
if ! command -v helm &> /dev/null; then
  info "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ─────────────────────────────────────────────────────────────────
# Step 2: Install Falco via Helm
# ─────────────────────────────────────────────────────────────────
info "Installing Falco..."

helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo update

helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set falcosidekick.enabled=true \
  --wait --timeout 600s

# ─────────────────────────────────────────────────────────────────
# Step 3: Verify
# ─────────────────────────────────────────────────────────────────
info "Verifying Falco installation..."
kubectl get pods -n falco

echo ""
echo "=========================================="
echo "  ✅ FALCO INSTALLED SUCCESSFULLY!"
echo "=========================================="
echo ""
info "Falco is now monitoring all containers for:"
echo "  • Shell spawned in container"
echo "  • Sensitive file access"
echo "  • Privilege escalation attempts"
echo "  • Unexpected network connections"
echo ""
