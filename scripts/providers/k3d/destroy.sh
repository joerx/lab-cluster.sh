#!/bin/bash

set -euo pipefail

log() {
  >&2 echo "$@"
}

NAME=${1:-"k3d-lab-$(hostname)"}

log "This will delete cluster '$NAME' and all data on it. Continue? (Ctrl-C to abort)"
read

k3d cluster delete $NAME
