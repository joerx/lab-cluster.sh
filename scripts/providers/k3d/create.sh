#!/bin/bash

set -euo pipefail

k3d cluster create --api-port 6550 -p "8080:80@loadbalancer" -p "8443:443@loadbalancer" --k3s-arg "--disable=traefik@server:0"
kubectl wait --for=condition=Ready nodes --all --timeout=120s
