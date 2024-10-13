#!/bin/bash

set -e -o pipefail

NAME=$1
MAX_ATTEMPTS=$2

if [[ -z $NAME ]]; then
  >&2 echo "$0 <NAME>"
  exit 1
fi

max=${MAX_ATTEMPTS:-5}

for ((i=1; i<=$max; i++)); do
  mac_addr=$(virsh dumpxml $NAME | grep "mac address" | sed "s/.*'\(.*\)'.*/\1/")

  set +e
  ip_addr=$(arp -n | grep "$mac_addr" | awk '{print $1}')
  set -e

  if [[ ! -z "$ip_addr" ]]; then
    echo $ip_addr
    exit 0
  fi

  sleep 1s
done

>&2 echo "Failed to get IP for '$NAME' after ${MAX}s, is the VM running?"
exit 1
