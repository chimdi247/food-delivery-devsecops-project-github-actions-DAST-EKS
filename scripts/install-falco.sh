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
  --set falcosidekick.enabled=true \
  --timeout 10m \
  --wait=false

echo "Waiting for Falco pods to be ready..."
# Falco is a DaemonSet — wait for at least 1 pod to be ready
for i in $(seq 1 60); do
  READY=$(kubectl get pods -n falco -l app.kubernetes.io/name=falco \
    -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$READY" = "True" ]; then
    echo "  ✅ Falco pod is Ready!"
    break
  fi
  if [ "$i" -eq "60" ]; then
    echo "  WARNING: Timed out. Falco may start after node is fully ready."
    kubectl get pods -n falco
    break
  fi
  echo "  Waiting... ($i/60)"
  sleep 10
done

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
