#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

RG_NAME="rg-fleet-commander-dev"
AKS_NAME="aks-fleet-commander-dev"

TRAEFIK_NAMESPACE="traefik"
ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="fleet"

echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RG_NAME" \
  --name "$AKS_NAME" \
  --overwrite-existing

echo "Checking nodes..."
kubectl get nodes

echo "Adding Helm repos..."
helm repo add traefik https://traefik.github.io/charts || true
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

echo "Creating namespaces..."
kubectl create namespace "$TRAEFIK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing/Upgrading Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace "$TRAEFIK_NAMESPACE"

kubectl rollout status deployment/traefik \
  -n "$TRAEFIK_NAMESPACE" \
  --timeout=180s

echo "Installing/Upgrading Fleet Commander via Helm..."
helm upgrade --install fleet ./helm/fleet-commander \
  --namespace "$APP_NAMESPACE"

kubectl rollout status deployment/fleet-fleet-commander \
  -n "$APP_NAMESPACE" \
  --timeout=180s

echo "Installing/Upgrading ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE"

kubectl rollout status deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=180s

echo "Status:"
kubectl get all -n "$APP_NAMESPACE"
kubectl get ingress -n "$APP_NAMESPACE"
kubectl get pods -n "$ARGOCD_NAMESPACE"

EXTERNAL_IP=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo ""
echo "Traefik External IP: $EXTERNAL_IP"
echo "Test app:"
echo "curl -H \"Host: fleet.local\" http://$EXTERNAL_IP/health"

echo ""
echo "ArgoCD UI:"
echo "kubectl port-forward svc/argocd-server -n argocd 8081:80"

echo ""
echo "ArgoCD admin password:"
echo "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"