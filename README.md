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

### Cluster Creation and Deletion

Create VM:

```sh
./vm-create.sh k3s-lab
```

Install k3s:

```sh
./scripts/install-k3s.sh k3s-lab
```

To connect to Kubernetes:

```sh
KUBECONFIG=$PWD/vms/k3s-lab/.kubecfg kubectl get node
```

Destroy VM (Will delete all data):

```sh
./vm-destroy.sh k3s-lab
```

### Bootstrapping

This should be relatively cluster-agnosting. However, it has only been tested with [k3d](https://k3d.io/stable/) for now. 

To install ArgoCD and bootstrap the cluster:

```sh
./scripts/bootstrap.sh --kubecfg $PWD/vms/k3s-lab/.kubecfg
```

Bootstrapping will install `ingress-nginx`, so it is recommented to disable the default ingress controller (if any) for the chosen provider. Example for `k3d`:

```sh
k3d cluster create --api-port 6550 -p "8080:80@loadbalancer" -p "8443:443@loadbalancer" --k3s-arg "--disable=traefik@server:0"
```

Note that `k3d` will update your default kubeconfig file, so the bootstrap command must be:

```sh
./scripts/bootstrap.sh --context k3d-k3s-default
```
