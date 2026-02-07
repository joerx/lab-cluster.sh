#!/bin/bash

set -e -o pipefail

log() {
  >&2 echo "$@"
}

usage() {
  >&2 echo "$0 <name>"
}


OS_VARIANT=centos-stream9
OS_ARCH=$(uname -m)

IMG_URL="https://cloud.centos.org/centos/9-stream/${OS_ARCH}/images/CentOS-Stream-GenericCloud-9-latest.${OS_ARCH}.qcow2"

NAME=${1:-"k3s-lab-$(hostname)"}

log "Creating VM '$NAME' with OS variant '$OS_VARIANT' and architecture '$OS_ARCH'"

BASEDIR=$(dirname $0)
IMGDIR=$(realpath $BASEDIR/../../../images)
VMDIR=$(realpath $BASEDIR/.vms)/$NAME

BASE_IMG=${OS_VARIANT}.${OS_ARCH}.qcow2

if [[ -d $VMDIR ]]; then
  >&2 echo "VM already exists, to re-create, run vm-destroy.sh first"
  exit 1
fi

if [[ ! -f "$IMGDIR/$BASE_IMG" ]]; then
  log "Base image for '$BASE_IMG' not found, downloading it to $IMGDIR/$BASE_IMG - this may take a while..."
  curl -fL $IMG_URL -o $IMGDIR/$BASE_IMG
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
    --ram 4096 \
    --vcpus 4 \
    --import \
    --disk path=$VMDIR/$NAME.qcow2,format=qcow2 \
    --disk path=$VMDIR/cidata.iso,device=cdrom \
    --os-variant=$OS_VARIANT \
    --memorybacking access.mode=shared \
    --filesystem source=$PWD,target=code,accessmode=passthrough,driver.type=virtiofs \
    --noautoconsole

log "VM '$NAME' created."
log "Getting IP address (this may take a few seconds)"

IP_ADDR=$($BASEDIR/_get-addr.sh $NAME 20)

log "Installing k3s on the VM '$NAME' at IP '$IP_ADDR' (this may take a few minutes)..."

$BASEDIR/_install-k3s.sh $NAME $IP_ADDR

log ""
log "--------------------------------------------------------------------------"
log "VM '$NAME' is ready and running k3s at IP address '$IP_ADDR'"
log "IP for '$NAME' is '$IP_ADDR'"
log "To add it to /etc/hosts:"
log "echo $IP_ADDR $NAME.local $NAME | sudo tee -a /etc/hosts"
log ""
log "To connect via SSH:"
log "ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" centos@$IP_ADDR"
log ""
log "To connect with kubectl:"
log "export KUBECONFIG=$VMDIR/.kubecfg"
log "kubectl cluster-info"
log "--------------------------------------------------------------------------"
log ""
