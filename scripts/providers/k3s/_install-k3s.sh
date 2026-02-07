#!/bin/bash

set -e -o pipefail

usage() {
  >&2 echo "$0 <name> <ip-address>"
}

log() {
  >&2 echo "$@"
}

NAME="$1"
IP_ADDR="$2"

if [[ -z "$NAME" || -z "$IP_ADDR" ]]; then
  usage
  exit 1
fi

BASEDIR=$(dirname $0)
VMDIR=$(realpath $BASEDIR/.vms)/$NAME

KUBECFG_OUT="$VMDIR/.kubecfg"

SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

# SSH login may fail on first attempt, add a retry loop to work around that
for i in {1..5}; do
  if ssh $SSH_OPTS -t centos@$IP_ADDR 'echo "connected to $HOSTNAME"'; then
    log "SSH connection successful on attempt $i"
    break
  fi
  log "SSH connection failed, retrying in 3 seconds..."
  sleep 3
done

# Install k3s inside the VM. We disable traefik and will install ingress-nginx instead later.
ssh $SSH_OPTS -t centos@$IP_ADDR 'echo "connected to $HOSTNAME"; curl -fL https://get.k3s.io | sh -s - --disable=traefik --write-kubeconfig-mode=644'

# Fetch the kubeconfig file from the VM, replacing the server with the VM's IP address
ssh $SSH_OPTS centos@$IP_ADDR -- cat /etc/rancher/k3s/k3s.yaml | sed "s/server: .*$/server: https:\/\/$IP_ADDR:6443/" > $KUBECFG_OUT
log "Kubernetes config written to $KUBECFG_OUT"

# Validate it worked and we can successfully connect to the cluster
CMD="KUBECONFIG=$KUBECFG_OUT kubectl cluster-info"
log "Running '$CMD' to validate"
eval $CMD
