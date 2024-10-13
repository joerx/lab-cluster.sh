#!/bin/bash

set -e -o pipefail

NAME=$1

VMDIR=vms/$NAME


usage() {
  >&2 echo "Usage: $0 <name>"
  exit 1
}


if [[ -z "$NAME" ]]; then
  usage
fi

if [[ ! -d $VMDIR ]]; then
  echo "VM '$NAME' not found, use vm-create.sh to create it."
  exit 1
fi

echo "This will destroy the VM and all data on it. Continue? (Ctrl-C to abort)"
read

virsh destroy $NAME || >&2 echo "...ignoring"
virsh undefine $NAME || >&2 echo "...ignoring"

# some files inside the .vm dir will be owned by qemu, don't have a better idea right now
# maybe try to run the whole thing in qemu://session instead?
sudo rm -rf $VMDIR
