# lab-cluster.sh

Collection of shell scripts to manage k3s lab clusters running various lightweight Kubernetes providers. This should be relatively distribution agnostic, but I am only testing on [k3s](https://k3s.io/) and [k3d](https://k3d.io/stable/) so far. 

This is more of an exercise for me than an attempt to build something useful for the general public. Leaving this here in case it is of any use to anyone.

Use cases:

- Lightweight lab cluster for local development
- Drop-in mini-cluster environment for edge deployments
- Command-and-control cluster for cloud control planes
- Embedded homelab on a Raspberry Pi or similar

Design Goals:

- Lightweight and modular for flexible use cases
- Highly automated and automatable
- Minimal glue code, rely on platform capabilities

## Usage

### Docker Based Cluster (k3d)

Basically `k3s` but running on Docker. More lightweight and easier to stand up than a VM based cluster and generally preferrable for most local application development purposes. This should also be relatively portable to alternative Kubernetes providers:

```
./scripts/providers/k3d/create.sh 
```

### VM Based Cluster (k3s)

Start a development VM using `libvirt` on a Linux host. Useful when developing base images and cluster bootstrap scripts or to fully isolate the k8s control plane from the host operating system.

We need a functioning setup of [KVM, QEMU and libvirt](https://joshrosso.com/docs/2020/2020-05-06-linux-hypervisor-setup/).


Fedora 

```sh
sudo dnf install @virtualization genisoimage
sudo systemctl enable libvirtd --now
```

- Tested only for `centos-stream9`
- If image is not found locally it will be downloaded from [CentOS Cloud Images](https://cloud.centos.org/centos/)

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

## Bootstrapping

This will install ArgoCD which will then bootstrap the cluster. This should be relatively cluster-agnostic. However, it has only been tested with k3d/k3s for now. The exact flags to pass into `bootstrap.sh` depend on the cluster connection details

The default will use whatever current `KUBECONFIG` and context are active:

```sh
./scripts/bootstrap.sh
```

By default this will only install ArgoCD and sync the initial ArgoCD bootstrap application and its dependencies for cert manager, Alloy, etc., but it will not sync those dependencies automatically. 

To enable auto-sync use the `--auto-sync` flag - This can also be turned on/off retroactively:

```sh
./scripts/bootstrap.sh --auto-sync
```

For a VM-based cluster, point `--kubecfg` to the kubernetes config file created as part of cluster creation:

```sh
./scripts/bootstrap.sh --kubecfg $PWD/vms/k3s-lab/.kubecfg --auto-sync
```

Creating a cluster using k3d will update your default kubeconfig file, so the bootstrap command must be:

```sh
./scripts/bootstrap.sh --context k3d-k3s-default --auto-sync
```

### ArgoCD Access

You can query ArgoCD applications and deployment status using `kubectl`:

```sh
kubectl get applications.argoproj.io -n argocd -w
```

To access the GUI, first get the ArgoCD admin password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

In a new terminal window, port-forward the ArgoCD service to port `8444`:

```sh
kubectl -n argocd port-forward services/argocd-server 8444:https
```

Open browser at [localhost:8444](https://localhost:8444), accept certificate error, log in with username 'admin' & password

### Ngrok Ingress Controller

> [!IMPORTANT]
> A ngrok account is needed for this. For a local development cluster everything can be done within the [free tier](https://ngrok.com/pricing).

The [ngrok kubernetes operator](https://ngrok.com/docs/k8s) allows ngrok public endpoints to be used as [Ingress](https://ngrok.com/docs/getting-started/kubernetes/ingress) or via the newer [Gateway API](https://ngrok.com/docs/getting-started/kubernetes/gateway-api). To enable the ngrok operator, you need an [API token](https://dashboard.ngrok.com/api) and [auth token](https://dashboard.ngrok.com/get-started/your-authtoken). Ensure these are set in your shell or `.env` file:

```sh
NGROK_API_KEY=_your_api_key_here_
NGROK_AUTHTOKEN=_your_auth_token_here_
```

Then bootstrap with the `--ngrok-enabled` flag:

```sh
./scripts/bootstrap.sh $(hostname)-k3d-lab --ngrok-enabled 
```

This [sample app](https://ngrok.com/docs/getting-started/kubernetes/ingress#3-deploy-a-sample-service) can be used to validate functionality.

**Important: Ngrok Resource Cleanup**

The ngrok operator uses a finaliser to clean up the Ngrok Operator resources registered in the backend. When destroying a cluster the finaliser may not be able to run and the operators in the [dashboard](https://dashboard.ngrok.com/kubernetes-operators) will get orphaned. We are intentionally _not_ attempting to clean them up as part of cluster deprovisioning [^1]. 

To periodically clean dangling endpoints (NB: This will delete ALL registered operators in your account [^2]): 

```
./scripts/misc/ngrok-cleanup.sh
```

[^1]: Doing so would leak problematic behaviour of a 3rd party operator into our toolchain and create complex, brittle code to maintain. The long-term maintenance drag is ultimately not worth the short term convenience gained.

[^2]: Haven't found a way to label or tag the remote resources in any predictable way yet, so for now make sure to use a dedicated account for dev
