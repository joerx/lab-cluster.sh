#!/bin/sh

# This script is designed to be idempotent, it should be safe to run multiple times
# This can be useful to update the deployed application if necessary.

set -e -o pipefail

MY_KUBECTX=""
MY_KUBECONFIG=""
NAME=""
NAMESPACE="argocd"
KEY_FILE="$HOME/.ssh/id_ed25519"
REPO_URL="git@github.com:joerx/lab-cluster.sh.git"
TARGET_REVISION=main
NGROK_ENABLED=false

log() {
  >&2 echo "$@"
}

usage() {
  log "Usage: $0 NAME [--kubecfg <path>] [--context <ctx>] [--ssh-key <path>] [--repo-url <url>] [--version <rev>]"
}

# Parse arguments

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
    --ngrok-enabled)
      NGROK_ENABLED="true"
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

# Validate NAME positional argument (first positional only)
if [[ -z "$NAME" ]]; then
  log "Provide the first positional argument as NAME. Other positional arguments are ignored."
  usage
  exit 1
fi

if [[ -f $PWD/.env ]]; then
  # shellcheck disable=SC1091
  log "Loading environment variables from $PWD/.env"
  . "$PWD/.env"
fi

# Validate input parameters
if [[ ! -f "$KEY_FILE" ]]; then
  log "SSH private key not found at $KEY_FILE. Please generate an SSH key pair to use with GitHub."
  usage
  exit 1
fi

# Secret Zero: All other secrets are stored in Infisical and will be retrieved using ESO
if [[ -z "$INFISICAL_UNIVERSAL_AUTH_CLIENT_ID" || -z "$INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET" ]]; then
  log "Infisical Universal Auth credentials not fully set in environment variables."
  log "Please set INFISICAL_UNIVERSAL_AUTH_CLIENT_ID and INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET."
  exit 1
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
if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
  log "ArgoCD is already installed in namespace '$NAMESPACE'. Skipping installation."
else
  log "Installing ArgoCD in namespace '$NAMESPACE'..."
  kubectl create namespace $NAMESPACE
  kubectl apply -n $NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

# Wait until we have at least one pod running
# Might be better to wait for the argocd-server pod specifically, but this is simpler
log "Waiting for ArgoCD server to be ready..."
kubectl -n $NAMESPACE wait deploy argocd-server --for jsonpath='{.status.availableReplicas}=1' --timeout=120s

# Create a secret for the GitHub repo credentials - we need to do this before we sync,
# so we can't use External Secrets for this one
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: lab-cluster-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: '$REPO_URL'
  sshPrivateKey: |
$(cat $KEY_FILE | sed 's/^/    /')
EOF

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
---
apiVersion: v1
kind: Secret
metadata:
  name: universal-auth-credentials
  namespace: external-secrets
stringData:
  clientId: ${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID}
  clientSecret: ${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET}
EOF

# Create a project for the bootstrap application
# It has privileged access, so it only allows access to the bootstrap repo
# We may need add specific repos for helm charts later
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: bootstrap
  namespace: argocd
spec:
  sourceRepos:
  - '$REPO_URL'
  - 'https://kubernetes.github.io/ingress-nginx'
  - 'https://grafana.github.io/helm-charts'
  - 'https://charts.jetstack.io'
  - 'https://ngrok.github.io/ngrok-operator'
  - 'https://charts.external-secrets.io'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
EOF

# Create an ArgoCD application for the lab cluster
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-bootstrap
  namespace: argocd
spec:
  project: bootstrap
  source:
    path: bootstrap
    repoURL: '$REPO_URL'
    targetRevision: '$TARGET_REVISION'
    helm:
      valuesObject:
        metadata:
          clusterName: '$NAME'
        ngrok:
          enabled: $NGROK_ENABLED
        source:
          repoUrl: '$REPO_URL'
          targetRevision: '$TARGET_REVISION'
        autosync:
          enabled: true
  destination:
    namespace: default
    server: 'https://kubernetes.default.svc'
  syncPolicy:
    automated:
      prune: true
EOF

# Print summary and help message
log
log "-------------------------------------------------------------------------"
log "ArgoCD application 'cluster-bootstrap' created in namespace '$NAMESPACE'."
log "You can get the status of the deployed applications with:"
log 
log "% kubectl -n $NAMESPACE get applications"
log
log "To get the ArgoCD admin password:"
log
log "% kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
log
log "To access the ArgoCD UI, run:"
log
log "% kubectl -n $NAMESPACE port-forward services/argocd-server 8444:https"
log
log "Then open your browser at https://localhost:8444 and log in with username" 
log "'admin' and the password above."
log "-------------------------------------------------------------------------"
log