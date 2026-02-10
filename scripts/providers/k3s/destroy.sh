#!/bin/bash

set -e -o pipefail

usage() {
  >&2 echo "Usage: $0 <name>"
  exit 1
}

NAME=${1:-"k3s-lab-$(hostname)"}

BASEDIR=$(dirname $0)
IMGDIR=$(realpath $BASEDIR/../../../images)
VMDIR=$(realpath $BASEDIR/.vms)/$NAME

if [[ ! -d $VMDIR ]]; then
  echo "VM '$NAME' not found, use vm-create.sh to create it."
  exit 1
fi

echo "This will destroy the VM '$NAME' and all data on it. Continue? (Ctrl-C to abort)"
read

virsh destroy $NAME || >&2 echo "...ignoring"
virsh undefine $NAME || >&2 echo "...ignoring"

# some files inside the .vm dir will be owned by qemu, don't have a better idea right now
# maybe try to run the whole thing in qemu://session instead?
sudo rm -rf $VMDIR
