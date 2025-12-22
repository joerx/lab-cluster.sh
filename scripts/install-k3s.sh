#!/bin/bash

set -e -o pipefail

NAME=$1

VMDIR=./vms/$NAME

KUBECFG_OUT="$VMDIR/.kubecfg"

if [[ -z $NAME ]]; then
  >&2 echo "$0 <NAME>"
  exit 1
fi

IP_ADDR=$(./vm-addr.sh $NAME 20)

SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

echo "VM '$NAME' has IP address: $IP_ADDR"

# Install k3s inside the VM. We disable traefik and will install ingress-nginx instead later.
ssh $SSH_OPTS -t centos@$IP_ADDR 'echo "connected to $HOSTNAME"; curl -fL https://get.k3s.io | sh -s - --disable=traefik --write-kubeconfig-mode=644'

# Fetch the kubeconfig file from the VM, replacing the server with the VM's IP address
ssh $SSH_OPTS centos@$IP_ADDR -- cat /etc/rancher/k3s/k3s.yaml | sed "s/server: .*$/server: https:\/\/$IP_ADDR:6443/" > $KUBECFG_OUT
echo "Kubernetes config written to $KUBECFG_OUT"

# Validate it worked and we can successfully connect to the cluster
CMD="KUBECONFIG=$KUBECFG_OUT kubectl cluster-info"
echo "Running '$CMD' to validate"
eval $CMD
