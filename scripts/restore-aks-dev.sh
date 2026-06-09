#!/usr/bin/env bash
set -euo pipefail

RG_NAME="rg-fleet-commander-dev"
AKS_NAME="aks-fleet-commander-dev"

TRAEFIK_NAMESPACE="traefik"
APP_NAMESPACE="fleet"

echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RG_NAME" \
  --name "$AKS_NAME" \
  --overwrite-existing

echo "Checking nodes..."
kubectl get nodes

echo "Installing/Updating Traefik Helm repo..."
helm repo add traefik https://traefik.github.io/charts || true
helm repo update

echo "Creating Traefik namespace..."
kubectl create namespace "$TRAEFIK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing/Upgrading Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace "$TRAEFIK_NAMESPACE"

echo "Waiting for Traefik pod..."
kubectl rollout status deployment/traefik -n "$TRAEFIK_NAMESPACE" --timeout=180s

echo "Creating app namespace..."
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying Fleet Commander manifests..."
kubectl apply -f k8s/base

echo "Waiting for Fleet Commander deployment..."
kubectl rollout status deployment/fleet-commander -n "$APP_NAMESPACE" --timeout=180s

echo "Current app status:"
kubectl get all -n "$APP_NAMESPACE"
kubectl get ingress -n "$APP_NAMESPACE"
kubectl get svc -n "$TRAEFIK_NAMESPACE"

echo ""
echo "External test:"
EXTERNAL_IP=$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Traefik External IP: $EXTERNAL_IP"
echo "Run:"
echo "curl -H \"Host: fleet.local\" http://$EXTERNAL_IP/health"
