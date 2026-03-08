#!/bin/sh

# This script is designed to be idempotent, it should be safe to run multiple times
# This can be useful to update the deployed application if necessary.

set -e -o pipefail

# Configuration precedence:
# 1. Default values in this script
# 2. Values from $PWD/.env file if it exists
# 3. Flags explicitly passed to this script
MY_KUBECTX=""
MY_KUBECONFIG=""
NAME=""
KEY_FILE="$HOME/.ssh/id_ed25519"
TARGET_REVISION=main
NGROK_ENABLED=false
AUTO_SYNC=false
EXTERNAL_DNS_ENABLED=false
INFISICAL_PROJECT="example-project"
INFISICAL_PATH="/shared/argocd/bootstrap"
DOMAIN=""
SECRET_STORE_BACKEND="kubernetes"

# Constants, cannot be set via flags or environment variables
REPO_URL=git@github.com:joerx/lab-cluster.sh.git
ARGO_NAMESPACE="argocd"
ARGO_CHART_VERSION="9.4.7"
EXTERNAL_SECRETS_NAMESPACE="external-secrets"

# Helper functions
log() {
  >&2 echo "$@"
}

usage() {
  log "Usage: $0 NAME [--kubecfg <path>] [--context <ctx>] [--ssh-key <path>] [--repo-url <url>] [--version <rev>]"
}

# Load .env file if exists
if [[ -f "$PWD/.env" ]]; then
  # shellcheck disable=SC1091
  log "Loading environment variables from $PWD/.env"
  source "$PWD/.env"
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubecfg)
      MY_KUBECONFIG="$2"
      shift 2
      ;;
    --context)
      MY_KUBECTX="$2"
      shift 2
      ;;
    --ssh-key)
      KEY_FILE="$2"
      shift 2
      ;;
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --version)
      TARGET_REVISION="$2"
      shift 2
      ;;
    --ngrok)
      NGROK_ENABLED="true"
      shift
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --external-dns)
      EXTERNAL_DNS_ENABLED="true"
      shift
      ;;
    --infisical-project)
      SECRET_STORE_BACKEND="infisical"
      INFISICAL_PROJECT="$2"
      shift 2
      ;;
    --infisical-path)
      SECRET_STORE_BACKEND="infisical"
      INFISICAL_PATH="$2"
      shift 2
      ;;
    --local)
      SECRET_STORE_BACKEND="kubernetes"
      shift
      ;;
    --auto-sync)
      AUTO_SYNC="true"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      log "Unknown option: $1"
      shift
      ;;
    *)
      # First non-option positional argument is NAME; discard the rest
      if [[ -z "$NAME" ]]; then
        NAME="$1"
      fi
      shift
      ;;
  esac
done

NAME=${NAME:-"k3s-lab-$(hostname)"}
DOMAIN=${DOMAIN:-"$NAME.local"}

log "Bootstrapping cluster '$NAME'"
log "- Repo URL: $REPO_URL"
log "- Target revision: $TARGET_REVISION"
log "- Domain: $DOMAIN"
log "- Secret store backend: $SECRET_STORE_BACKEND"
if [[ "$SECRET_STORE_BACKEND" == "infisical" ]]; then
  log "- Infisical project: $INFISICAL_PROJECT"
  log "- Infisical path: $INFISICAL_PATH"
fi


# Validate input parameters
if [[ ! -f "$KEY_FILE" ]]; then
  log "SSH private key not found at $KEY_FILE. Please generate an SSH key pair to use with GitHub."
  usage
  exit 1
fi

# Secret Zero: All other secrets are stored in Infisical and will be retrieved using ESO.
# Not required when using the fake backend for local clusters.
if [[ "$SECRET_STORE_BACKEND" == "infisical" ]]; then
  if [[ -z "$INFISICAL_UNIVERSAL_AUTH_CLIENT_ID" || -z "$INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET" ]]; then
    log "Infisical Universal Auth credentials not fully set in environment variables."
    log "Please set INFISICAL_UNIVERSAL_AUTH_CLIENT_ID and INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET."
    log "For local clusters without Infisical, use the --local flag."
    exit 1
  fi
fi

# Set kubernetes config and context if provided
if [[ ! -z "$MY_KUBECONFIG" ]]; then
  log "Using kube config $MY_KUBECONFIG"
  export KUBECONFIG=$MY_KUBECONFIG
fi

if [[ ! -z "$MY_KUBECTX" ]]; then
  kubectl config use-context "$MY_KUBECTX"
else
  log "Using default kubectl context"
fi

# Check if ArgoCD is already installed, skip installation if it is
if kubectl get namespace $ARGO_NAMESPACE >/dev/null 2>&1; then
  log "ArgoCD is already installed in namespace '$ARGO_NAMESPACE'. Skipping installation."
else
  log "Installing ArgoCD in namespace '$ARGO_NAMESPACE'..."
  helm install argo-cd argo-cd \
    --repo https://argoproj.github.io/argo-helm \
    --version $ARGO_CHART_VERSION \
    --namespace $ARGO_NAMESPACE \
    --create-namespace
fi

# Wait until we have at least one pod running
log "Waiting for ArgoCD server to be ready..."
kubectl -n $ARGO_NAMESPACE wait deploy argo-cd-argocd-server --for jsonpath='{.status.availableReplicas}=1' --timeout=120s

# Install the Application for ArgoCD to sync the bootstrap stack
# Creates a project for the bootstrap application. Helm values passed here 
# are used to toggle and configure the clusters core features
helm upgrade --install bootstrap-argo ./charts/bootstrap-argo \
  --namespace $ARGO_NAMESPACE \
  --set "cluster.name=$NAME" \
  --set "cluster.domain=$DOMAIN" \
  --set "externalDNS.enabled=$EXTERNAL_DNS_ENABLED" \
  --set "source.repoURL=$REPO_URL" \
  --set "source.targetRevision=$TARGET_REVISION" \
  --set-file "source.sshPrivateKey=$KEY_FILE" \
  --set "autosync.enabled=$AUTO_SYNC" \
  --set "secretStore.backend=$SECRET_STORE_BACKEND" \
  --set "infisical.project=$INFISICAL_PROJECT" \
  --set "infisical.path=$INFISICAL_PATH"

# Installs the secret with the initial credentials (infisical backend) or seeds the
# local-secrets namespace (kubernetes backend). Everything after that is managed by
# ArgoCD, which deploys the external-secrets chart and ClusterSecretStores.
helm upgrade --install bootstrap-secrets ./charts/bootstrap-secrets \
  --namespace $EXTERNAL_SECRETS_NAMESPACE \
  --create-namespace \
  --set "backend=$SECRET_STORE_BACKEND" \
  --set "universalAuth.clientId=${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}" \
  --set "universalAuth.clientSecret=${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}" \
  --set "localSecrets.grafana.GCLOUD_K8S_RW_TOKEN=${GCLOUD_K8S_RW_TOKEN:-}" \
  --set "localSecrets.grafana.GCLOUD_HOSTED_LOGS_ID=${GCLOUD_HOSTED_LOGS_ID:-}" \
  --set "localSecrets.grafana.GCLOUD_HOSTED_METRICS_ID=${GCLOUD_HOSTED_METRICS_ID:-}" \
  --set "localSecrets.externalDns.LINODE_TOKEN=${LINODE_TOKEN:-}"

# Print summary and help message
log
log "-------------------------------------------------------------------------"
log "ArgoCD application 'cluster-bootstrap' created in namespace '$ARGO_NAMESPACE'."
log "You can get the status of the deployed applications with:"
log 
log "% kubectl -n $ARGO_NAMESPACE get applications"
log
log "To get the ArgoCD admin password:"
log
log "% kubectl -n $ARGO_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
log
log "To access the ArgoCD UI, run:"
log
log "% kubectl -n $ARGO_NAMESPACE port-forward services/argo-cd-argocd-server 8444:https"
log
log "Then open your browser at https://localhost:8444 and log in with username" 
log "'admin' and the password above."
log "-------------------------------------------------------------------------"
log