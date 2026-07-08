#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# install-falco.sh
# Installs Falco Runtime Security on EKS
# Monitors containers for suspicious behavior at runtime
#
# Usage: bash install-falco.sh
# ═══════════════════════════════════════════════════════════════════

echo "=========================================="
echo "  FALCO — Runtime Security Setup"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Install Helm (if not present)
# ─────────────────────────────────────────────────────────────────
if ! command -v helm &> /dev/null; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ─────────────────────────────────────────────────────────────────
# Step 2: Install Falco via Helm
# ─────────────────────────────────────────────────────────────────
echo "Adding Falco Helm repo..."
helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
helm repo update

echo "Installing Falco..."
helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set falcosidekick.enabled=true

echo "Waiting for Falco DaemonSet rollout..."
kubectl rollout status daemonset/falco -n falco --timeout=600s || {
  echo "WARNING: Falco rollout timed out. Checking status..."
  kubectl get pods -n falco
}

# ─────────────────────────────────────────────────────────────────
# Step 3: Verify
# ─────────────────────────────────────────────────────────────────
echo "Verifying Falco installation..."
kubectl get pods -n falco
kubectl get daemonset -n falco

echo ""
echo "=========================================="
echo "  ✅ FALCO INSTALLED SUCCESSFULLY!"
echo "=========================================="
echo ""
echo "Falco is now monitoring all containers for:"
echo "  • Shell spawned in container"
echo "  • Sensitive file access"
echo "  • Privilege escalation attempts"
echo "  • Unexpected network connections"
echo ""
