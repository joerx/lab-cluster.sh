# lab-cluster.sh

Collection of shell scripts to manage k3s lab clusters running on `libvirt` VMs. Why? Because I can. 🤷🏻‍♂️

## Disclaimer

This is more of an exercise for me than an attempt to build something useful for the general public. Leaving this here in case it is of any use to anyone.

## Preconditions

This tool has been tested only for `centos-stream9`. You need to download the base image yourself:

```sh
ARCH=$(uname -m)
curl https://cloud.centos.org/centos/9-stream/${ARCH}/images/CentOS-Stream-GenericCloud-9-latest.${ARCH}.qcow2 -o images/centos-stream9.${ARCH}.qcow2
```

## Usage

Create VM:

```sh
./vm-create.sh k3s-lab
```

Install k3s:

```sh
./install-k3s.sh k3s-lab
```

To connect to Kubernetes:

```sh
KUBECONFIG=$PWD/vms/k3s-lab/.kubecfg kubectl get node
```

Destroy VM (Will delete all data):

```sh
./vm-destroy.sh k3s-lab
```
