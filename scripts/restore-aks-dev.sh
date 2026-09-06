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
FLEET_NAMESPACE="fleet"

# Try to detect Terraform directory.
# Adjust this manually if your Terraform folder has a different name.
if [[ -d "$REPO_ROOT/terraform" ]]; then
  TERRAFORM_DIR="$REPO_ROOT/terraform"
elif [[ -d "$REPO_ROOT/infra" ]]; then
  TERRAFORM_DIR="$REPO_ROOT/infra"
else
  TERRAFORM_DIR=""
fi

echo "Getting Terraform outputs if available..."

KEY_VAULT_NAME=""
TENANT_ID=""
FLEET_IDENTITY_CLIENT_ID=""

if [[ -n "$TERRAFORM_DIR" ]]; then
  pushd "$TERRAFORM_DIR" >/dev/null

  KEY_VAULT_NAME="$(terraform output -raw key_vault_name 2>/dev/null || true)"
  TENANT_ID="$(terraform output -raw tenant_id 2>/dev/null || true)"
  FLEET_IDENTITY_CLIENT_ID="$(terraform output -raw fleet_identity_client_id 2>/dev/null || true)"

  popd >/dev/null
else
  echo "Terraform directory not found. Skipping Terraform outputs."
fi

echo ""
echo "Restore context:"
echo "Resource group: $RG_NAME"
echo "AKS name: $AKS_NAME"
echo "Terraform dir: ${TERRAFORM_DIR:-not found}"
echo "Key Vault name: ${KEY_VAULT_NAME:-not available}"
echo "Tenant ID: ${TENANT_ID:-not available}"
echo "Fleet identity client ID: ${FLEET_IDENTITY_CLIENT_ID:-not available}"

echo ""
echo "Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RG_NAME" \
  --name "$AKS_NAME" \
  --overwrite-existing

echo ""
echo "Checking nodes..."
kubectl get nodes

echo ""
echo "Adding Helm repos..."
helm repo add traefik https://traefik.github.io/charts || true
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

echo ""
echo "Creating namespaces..."
kubectl create namespace "$FLEET_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$TRAEFIK_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Installing/Upgrading Traefik..."
helm upgrade --install traefik traefik/traefik \
  --namespace "$TRAEFIK_NAMESPACE"

kubectl rollout status deployment/traefik \
  -n "$TRAEFIK_NAMESPACE" \
  --timeout=180s

echo ""
echo "Installing/Upgrading kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE"

echo ""
echo "Installing/Upgrading ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE"

kubectl rollout status deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" \
  --timeout=180s

echo ""
echo "Applying ArgoCD repository secret if file exists..."
if [[ -f "argocd/repo-secret.yaml" ]]; then
  kubectl apply -f argocd/repo-secret.yaml
else
  echo "argocd/repo-secret.yaml not found. If repo is private, create repo credentials manually."
fi

echo ""
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

echo ""
echo "Applying ArgoCD root application..."
kubectl apply -f argocd/root-application.yaml

echo ""
echo "Waiting a bit for ArgoCD reconciliation..."
sleep 20

echo ""
echo "Applications:"
kubectl get applications -n "$ARGOCD_NAMESPACE" || true

echo ""
echo "Fleet status:"
kubectl get all -n "$FLEET_NAMESPACE" || true
kubectl get ingress -n "$FLEET_NAMESPACE" || true

echo ""
echo "Monitoring status:"
kubectl get pods -n "$MONITORING_NAMESPACE" | head || true
kubectl get servicemonitor -A | grep fleet || true

echo ""
echo "Checking Key Vault secret..."

if [[ -n "$KEY_VAULT_NAME" ]]; then
  echo "Checking secret captain-name in Key Vault: $KEY_VAULT_NAME"

  az keyvault secret show \
    --vault-name "$KEY_VAULT_NAME" \
    --name captain-name \
    --query "{name:name, value:value}" \
    -o table || {
      echo "Could not read captain-name from Key Vault."
      echo "Possible reasons:"
      echo "- current Azure user does not have secrets Get permission"
      echo "- secret captain-name was not created"
      echo "- Key Vault name is wrong"
    }
else
  echo "Skipping Key Vault check because key_vault_name output is missing."
fi

echo ""
echo "Checking CSI Driver status..."

if kubectl get crd secretproviderclasses.secrets-store.csi.x-k8s.io >/dev/null 2>&1; then
  echo "SecretProviderClass CRD exists."
  echo ""
  echo "CSI-related pods:"
  kubectl get pods -n kube-system | grep -E "secrets-store|provider-azure" || true
else
  echo "CSI Driver is not enabled yet."
  echo ""
  echo "Tomorrow's next Terraform step:"
  echo ""
  echo "Add this block to azurerm_kubernetes_cluster:"
  echo ""
  echo "key_vault_secrets_provider {"
  echo "  secret_rotation_enabled = true"
  echo "}"
fi

echo ""
echo "Traefik external IP:"
EXTERNAL_IP="$(kubectl get svc traefik -n "$TRAEFIK_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

if [[ -n "$EXTERNAL_IP" ]]; then
  echo "$EXTERNAL_IP"
else
  echo "Traefik external IP is not ready yet."
  echo "Check later:"
  echo "kubectl get svc traefik -n $TRAEFIK_NAMESPACE"
fi

echo ""
echo "Test app:"
if [[ -n "$EXTERNAL_IP" ]]; then
  echo "curl -H \"Host: fleet.local\" http://$EXTERNAL_IP/health"
else
  echo "Wait for Traefik external IP first."
fi

echo ""
echo "Grafana:"
echo "kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"

echo ""
echo "ArgoCD UI:"
echo "kubectl port-forward svc/argocd-server -n argocd 8081:80"

echo ""
echo "Useful commands for tomorrow:"
echo ""
echo "Terraform outputs:"
if [[ -n "$TERRAFORM_DIR" ]]; then
  echo "cd $TERRAFORM_DIR"
else
  echo "cd terraform"
fi
echo "terraform output key_vault_name"
echo "terraform output tenant_id"
echo "terraform output fleet_identity_client_id"

echo ""
echo "Check CSI Driver:"
echo "kubectl get pods -n kube-system | grep secrets-store"
echo "kubectl get crd | grep secretprovider"

echo ""
echo "After SecretProviderClass and volume mount are added:"
echo "kubectl exec -n fleet deploy/fleet-commander -- ls /mnt/secrets-store"
echo "kubectl exec -n fleet deploy/fleet-commander -- cat /mnt/secrets-store/captain-name"

echo ""
echo "Next practical step:"
echo "Key Vault -> CSI Driver -> /mnt/secrets-store/captain-name inside Fleet Commander pod"