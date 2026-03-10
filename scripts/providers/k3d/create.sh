#!/bin/bash

set -euo pipefail

MEMORY_LIMIT=12GB

log() {
  >&2 echo "$@"
}

fatal() {
  log "$@"
  exit 1
}

NAME=${1:-"k3d-lab-$(hostname)"}

if ! which k3d > /dev/null 2>&1; then
  fatal "k3d is not installed, aborting"
fi

if ! which kubectl > /dev/null 2>&1; then
  fatal "kubectl is not installed, aborting"
fi

log "Creating cluster '$NAME'"

k3d cluster create $NAME\
  --api-port 6550 \
  -p "8080:80@loadbalancer" \
  -p "8443:443@loadbalancer" \
  --servers-memory "${MEMORY_LIMIT}" \
  --k3s-arg "--disable=traefik@server:0"

kubectl wait --for=condition=Ready nodes --all --timeout=120s
