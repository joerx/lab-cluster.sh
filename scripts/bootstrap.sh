#!/bin/sh

set -e -o pipefail

KUBECONFIG=""
KUBECTX=""
NAMESPACE="argocd"
KEY_FILE="$HOME/.ssh/id_ed25519"
REPO_URL="git@github.com:joerx/lab-cluster.sh.git"
TARGET_REVISION=argo-bootstrap

log() {
  >&2 echo "$@"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubecfg)
      KUBECONFIG="$2"
      shift 2
      ;;
    --context)
      KUBECTX="$2"
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
    *)
      shift
      ;;
  esac
done

# Validate input parameters

if [[ ! -f "$KEY_FILE" ]]; then
  log "SSH private key not found at $KEY_FILE. Please generate an SSH key pair to use with GitHub."
  exit 1
fi

# Set kubernetes config and context if provided

if [[ ! -z "$KUBECONFIG" ]]; then
  log "Using kube config $KUBECTX"
  export KUBECONFIG
fi

if [[ ! -z "$KUBECTX" ]]; then
  kubectl config use-context "$KUBECTX"
else
  KUBECTX=$(kubectl config current-context)
  log "Using current context: $KUBECTX"
fi

# Check if ArgoCD is already installed, skip installation if it is
if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
  log "ArgoCD is already installed in namespace '$NAMESPACE'. Skipping installation."
else
  kubectl create namespace $NAMESPACE
  kubectl apply -n $NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
fi

# Wait until we have at least one pod running
# Might be better to wait for the argocd-server pod specifically, but this is simpler
log "Waiting for ArgoCD server to be ready..."
kubectl -n $NAMESPACE wait deploy argocd-server --for jsonpath='{.status.availableReplicas}=1' --timeout=60s

# Create a secret for the GitHub repo credentials
# NB: kubectl apply operations are idempotent, so we can safely run them multiple times
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
  - 'https://prometheus-community.github.io/helm-charts'
  - 'https://charts.jetstack.io'
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
    path: bootstrap/manifests
    repoURL: '$REPO_URL'
    targetRevision: '$TARGET_REVISION'
  destination:
    namespace: default
    server: 'https://kubernetes.default.svc'
  syncPolicy:
    automated:
      prune: true
EOF

log
log "-------------------------------------------------------------------------"
log "ArgoCD application 'cluster-bootstrap' created in namespace '$NAMESPACE'."
log "You can get the status of the deployed applications with:"
log 
log "% kubectl -n $NAMESPACE get applications"
log
log "To access the ArgoCD UI, run:"
log
log "% kubectl -n $NAMESPACE port-forward services/argocd-server 8444:https"
log
log "To get the ArgoCD admin password:"
log
log "% kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
log
log "Then open your browser at https://localhost:8444 and log in with username" 
log "'admin' and the password above."
log "-------------------------------------------------------------------------"
log