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
AUTHELIA_ENABLED=false
AUTO_SYNC=false
AUTHELIA_USERS_FILE=""

cleanup() {
  [[ -n "$AUTHELIA_USERS_FILE" ]] && rm -f "$AUTHELIA_USERS_FILE"
}
trap cleanup EXIT
EXTERNAL_DNS_ENABLED=false
INFISICAL_PROJECT="example-project"
INFISICAL_PATH="/shared/argocd/bootstrap"
DOMAIN=""
SECRET_STORE_BACKEND="kubernetes"
LETSENCRYPT_ENABLED=false
GHCR_USERNAME=""
GHCR_TOKEN=""

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
  cat >&2 <<EOF
Usage: $0 [NAME] [options]

  NAME  Cluster name (default: k3s-lab-<hostname>)

Options:
  --kubecfg <path>            Path to kubeconfig file (default: current KUBECONFIG)
  --context <ctx>             Kubernetes context to use (default: current context)
  --ssh-key <path>            SSH private key for repo access (default: ~/.ssh/id_ed25519)
  --repo-url <url>            Git repository URL (default: $REPO_URL)
  --version <rev>             Git target revision (default: main)
  --domain <domain>           Cluster domain (default: <name>.local)
  --auto-sync                 Enable ArgoCD auto-sync (default: off)
  --letsencrypt               Enable Let's Encrypt certificates (requires --external-dns)
  --external-dns              Enable external-dns (Linode)
  --ngrok                     Enable ngrok ingress controller
  --infisical-project <id>    Infisical project ID; enables Infisical secret backend
  --infisical-path <path>     Infisical secret path (default: $INFISICAL_PATH)
  --local                     Force local kubernetes secret backend
  --ghcr-username <user>      GitHub Container Registry username
  --ghcr-token <token>        GitHub Container Registry token

Environment variables:
  GITHUB_TOKEN                            Used as GHCR token if --ghcr-token is not set
  INFISICAL_UNIVERSAL_AUTH_CLIENT_ID      Required when --infisical-project is set
  INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET  Required when --infisical-project is set
  LINODE_TOKEN                            Required when --external-dns is set
  NGROK_API_KEY                           Required when --ngrok is set
  NGROK_AUTHTOKEN                         Required when --ngrok is set
  AUTHELIA_ADMIN_PASSWORD                 Required when --authelia is set
  GCLOUD_K8S_RW_TOKEN                     Grafana Cloud token (kubernetes backend only)
  GCLOUD_HOSTED_LOGS_ID                   Grafana Cloud logs instance ID (kubernetes backend only)
  GCLOUD_HOSTED_METRICS_ID                Grafana Cloud metrics instance ID (kubernetes backend only)

  When using the kubernetes backend (default), credentials are read from environment
  variables and seeded into the cluster. See .env.example for the full list.
EOF
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
    --letsencrypt)
      LETSENCRYPT_ENABLED="true"
      shift
      ;;
    --authelia)
      AUTHELIA_ENABLED="true"
      shift
      ;;
    --ghcr-username)
      GHCR_USERNAME="$2"
      shift 2
      ;;
    --ghcr-token)
      GHCR_TOKEN="$2"
      shift 2
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
GHCR_USERNAME=${GHCR_USERNAME:-$(git config user.name 2>/dev/null || true)}
GHCR_TOKEN=${GHCR_TOKEN:-${GITHUB_TOKEN:-}}

log "Bootstrapping cluster '$NAME'"
log "- Repo URL: $REPO_URL"
log "- Auto sync: $AUTO_SYNC"
log "- Target revision: $TARGET_REVISION"
log "- Domain: $DOMAIN"
log "- Secret store backend: $SECRET_STORE_BACKEND"
if [[ "$SECRET_STORE_BACKEND" == "infisical" ]]; then
  log "- Infisical project: $INFISICAL_PROJECT"
  log "- Infisical path: $INFISICAL_PATH"
fi

# Validate input parameters
if [[ "$AUTHELIA_ENABLED" == "true" ]]; then
  [[ -z "${AUTHELIA_ADMIN_PASSWORD:-}" ]] && { log "error: --authelia requires AUTHELIA_ADMIN_PASSWORD"; exit 1; }
fi

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

log "Installing/upgrading ArgoCD in namespace '$ARGO_NAMESPACE'..."
helm upgrade --install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version $ARGO_CHART_VERSION \
  --namespace $ARGO_NAMESPACE \
  --create-namespace \
  --values ./helm/argocd.yaml \
  --set "server.ingress.hostname=argocd.$DOMAIN"

# Wait until we have at least one pod running
log "Waiting for ArgoCD server to be ready..."
kubectl -n $ARGO_NAMESPACE wait deploy argo-cd-argocd-server --for jsonpath='{.status.availableReplicas}=1' --timeout=120s

# Install the Application for ArgoCD to sync the bootstrap stack
# Creates a project for the bootstrap application. Helm values passed here 
# are used to toggle and configure the clusters core features
ARGO_ARGS=(
  upgrade --install bootstrap-argo ./charts/bootstrap-argo
  --namespace "$ARGO_NAMESPACE"
  --set "cluster.name=$NAME"
  --set "cluster.domain=$DOMAIN"
  --set "externalDNS.enabled=$EXTERNAL_DNS_ENABLED"
  --set "source.repoURL=$REPO_URL"
  --set "source.targetRevision=$TARGET_REVISION"
  --set-file "source.sshPrivateKey=$KEY_FILE"
  --set "autosync.enabled=$AUTO_SYNC"
  --set "secretStore.backend=$SECRET_STORE_BACKEND"
  --set "infisical.project=$INFISICAL_PROJECT"
  --set "infisical.path=$INFISICAL_PATH"
  --set "letsencrypt.enabled=$LETSENCRYPT_ENABLED"
  --set "ghcr.username=${GHCR_USERNAME:-}"
  --set "ghcr.token=${GHCR_TOKEN:-}"
)

[[ "$AUTHELIA_ENABLED" == "true" ]] && ARGO_ARGS+=(--set "authelia.enabled=true")

helm "${ARGO_ARGS[@]}"

# Installs the secret with the initial credentials (infisical backend) or seeds the
# local-secrets namespace (kubernetes backend). Everything after that is managed by
# ArgoCD, which deploys the external-secrets chart and ClusterSecretStores.
SECRETS_ARGS=(
  upgrade --install bootstrap-secrets ./charts/bootstrap-secrets
  --namespace "$EXTERNAL_SECRETS_NAMESPACE"
  --create-namespace
  --set "backend=$SECRET_STORE_BACKEND"
  --set "universalAuth.clientId=${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}"
  --set "universalAuth.clientSecret=${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}"
  --set "localSecrets.grafana.GCLOUD_K8S_RW_TOKEN=${GCLOUD_K8S_RW_TOKEN:-}"
  --set "localSecrets.grafana.GCLOUD_HOSTED_LOGS_ID=${GCLOUD_HOSTED_LOGS_ID:-}"
  --set "localSecrets.grafana.GCLOUD_HOSTED_METRICS_ID=${GCLOUD_HOSTED_METRICS_ID:-}"
  --set "localSecrets.externalDns.LINODE_TOKEN=${LINODE_TOKEN:-}"
)

if [[ "$AUTHELIA_ENABLED" == "true" && "$SECRET_STORE_BACKEND" == "kubernetes" ]]; then
  log "Generating Authelia users database..."
  AUTHELIA_PASSWORD_HASH=$(openssl passwd -6 "${AUTHELIA_ADMIN_PASSWORD}")
  AUTHELIA_USERS_FILE=$(mktemp)
  cat > "$AUTHELIA_USERS_FILE" <<EOF
localSecrets:
  authelia:
    usersDatabase: |
      users:
        admin:
          displayname: Admin
          password: "${AUTHELIA_PASSWORD_HASH}"
          email: admin@${DOMAIN}
          groups:
            - admins
EOF
  SECRETS_ARGS+=(--values "$AUTHELIA_USERS_FILE")
fi

if [[ "$AUTHELIA_ENABLED" == "true" && "$SECRET_STORE_BACKEND" == "infisical" ]]; then
  log "warning: --authelia with infisical backend requires manual seeding of the authelia-users secret"
  log "  store users_database.yml content at key 'users_database.yml' under 'authelia-users' in Infisical"
fi

helm "${SECRETS_ARGS[@]}"

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
log "To access the ArgoCD UI:"
log
log "  https://argocd.$DOMAIN  (once ingress-nginx and cert-manager have synced)"
log
log "Or via port-forward before ingress is ready:"
log
log "% kubectl -n $ARGO_NAMESPACE port-forward services/argo-cd-argocd-server 8080:80"
log
log "Then open your browser at http://localhost:8080 and log in with username"
log "'admin' and the password above."
log "-------------------------------------------------------------------------"
log