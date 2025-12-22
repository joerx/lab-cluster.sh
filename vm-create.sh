#!/bin/bash

set -e -o pipefail

OS_VARIANT=centos-stream9
OS_ARCH=$(uname -m)

# TODO: make this dynamic, download image if not exists
IMGDIR=$(realpath $(dirname $0)/images)

BASE_IMG=${OS_VARIANT}.${OS_ARCH}.qcow2

NAME=$1

VMDIR=vms/$NAME


log() {
  >&2 echo "$@"
}

usage() {
  >&2 echo "$0 <name>"
  exit 1
}


if [[ -z "$NAME" ]]; then
  usage
fi

if [[ ! -f "$IMGDIR/$BASE_IMG" ]]; then
  >&2 echo "Base image for '$BASE_IMG' not found, please download and place it in $IMGDIR"
  exit 1
fi

if [[ -d $VMDIR ]]; then
  >&2 echo "VM already exists, to re-create, run vm-destroy.sh first"
  exit 1
fi

mkdir -p $VMDIR

SSH_RSA=$(cat ~/.ssh/id_ed25519.pub)

# Generate meta-data and user-data files
cat << EOF > $VMDIR/meta-data
instance-id: $NAME
local-hostname: $NAME
EOF

cat << EOF > $VMDIR/user-data
#cloud-config

users:
  - name: centos
    ssh_authorized_keys:
      - $SSH_RSA
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
EOF

# Generate file system from base image
qemu-img create -b $IMGDIR/$BASE_IMG -f qcow2 -F qcow2 $VMDIR/$NAME.qcow2 10G

# Generate ISO image for cloudinit
genisoimage -output $VMDIR/cidata.iso -V cidata -r -J $VMDIR/user-data $VMDIR/meta-data

# Virt-install
virt-install \
    --name $NAME \
    --ram 2048 \
    --vcpus 2 \
    --import \
    --disk path=$VMDIR/$NAME.qcow2,format=qcow2 \
    --disk path=$VMDIR/cidata.iso,device=cdrom \
    --os-variant=$OS_VARIANT \
    --memorybacking access.mode=shared \
    --filesystem source=$PWD,target=code,accessmode=passthrough,driver.type=virtiofs \
    --noautoconsole

log "VM '$NAME' created."
log "Getting IP address (this may take a few seconds)"

IP_ADDR=$(./vm-addr.sh $NAME 20)

log "IP for '$NAME' is '$IP_ADDR'"
log "To add it to /etc/hosts:"
log "echo $IP_ADDR $NAME.local $NAME | sudo tee -a /etc/hosts"
log ""
log "To connect:"
log "ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" centos@192.168.122.28"
