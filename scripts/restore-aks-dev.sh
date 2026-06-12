#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

RG_NAME="rg-fleet-commander-dev"
AKS_NAME="aks-fleet-commander-dev"

TRAEFIK_NAMESPACE="traefik"
ARGOCD_NAMESPACE="argocd"
MONITORING_NAMESPACE="monitoring"

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
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

echo "Creating namespaces..."
kubectl create namespace "$TRAEFIK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing/Upgrading Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace "$TRAEFIK_NAMESPACE"

kubectl rollout status deployment/traefik \
  -n "$TRAEFIK_NAMESPACE" \
  --timeout=180s

echo "Installing/Upgrading kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE"

echo "Installing/Upgrading ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE"

kubectl rollout status deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=180s

echo "Applying ArgoCD repository secret if file exists..."
if [[ -f "argocd/repo-secret.yaml" ]]; then
  kubectl apply -f argocd/repo-secret.yaml
else
  echo "argocd/repo-secret.yaml not found. If repo is private, create repo credentials manually."
fi

echo "Creating ArgoCD repository secret..."

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "ERROR: GITHUB_TOKEN is not set."
  echo "Run: export GITHUB_TOKEN=your_github_token"
  exit 1
fi

kubectl create secret generic fleet-commander-repo \
  -n "$ARGOCD_NAMESPACE" \
  --from-literal=type=git \
  --from-literal=url=https://github.com/vholubiuk/fleet-commander.git \
  --from-literal=username=vholubiuk \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret fleet-commander-repo \
  -n "$ARGOCD_NAMESPACE" \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "Applying ArgoCD root application..."
kubectl apply -f argocd/root-application.yaml

echo "Waiting a bit for ArgoCD reconciliation..."
sleep 20

echo "Applications:"
kubectl get applications -n "$ARGOCD_NAMESPACE"

echo ""
echo "Fleet status:"
kubectl get all -n fleet || true
kubectl get ingress -n fleet || true

echo ""
echo "Monitoring status:"
kubectl get pods -n "$MONITORING_NAMESPACE" | head
kubectl get servicemonitor -A | grep fleet || true

echo ""
echo "Traefik external IP:"
EXTERNAL_IP=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$EXTERNAL_IP"

echo ""
echo "Test app:"
echo "curl -H \"Host: fleet.local\" http://$EXTERNAL_IP/health"

echo ""
echo "Grafana:"
echo "kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"

echo ""
echo "ArgoCD UI:"
echo "kubectl port-forward svc/argocd-server -n argocd 8081:80"