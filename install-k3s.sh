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

ssh -t centos@$IP_ADDR 'curl -sfL https://get.k3s.io | sh -s - --disable=traefik --write-kubeconfig-mode=644'

ssh centos@$IP_ADDR -- cat /etc/rancher/k3s/k3s.yaml | sed "s/server: .*$/server: https:\/\/$IP_ADDR:6443/" > $KUBECFG_OUT

echo "Kubernetes config written to $KUBECFG_OUT"

CMD="KUBECONFIG=$KUBECFG_OUT kubectl get node"

echo "Running '$CMD' to validate"
eval $CMD
