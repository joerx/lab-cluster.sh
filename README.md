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

## Configuration

All features are configured via CLI flags and/or environment variables. For local development, place a `.env` file in the working directory — it will be sourced automatically. Copy `.env.example` to get started:

```sh
cp .env.example .env
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `NAME` | `k3s-lab-<hostname>` | Cluster name (positional) |
| `--kubecfg <path>` | current `KUBECONFIG` | Path to kubeconfig file |
| `--context <ctx>` | current context | Kubernetes context to use |
| `--ssh-key <path>` | `~/.ssh/id_ed25519` | SSH private key for repo access |
| `--repo-url <url>` | repo default | Git repository URL |
| `--version <rev>` | `main` | Git target revision |
| `--domain <domain>` | `<name>.local` | Cluster domain |
| `--auto-sync` | off | Enable ArgoCD auto-sync |
| `--letsencrypt` | off | Enable Let's Encrypt (requires `--external-dns`) |
| `--external-dns` | off | Enable external-dns via Linode |
| `--ngrok` | off | Enable ngrok ingress controller |
| `--infisical-project <id>` | — | Infisical project ID; switches to Infisical secret backend |
| `--infisical-path <path>` | `/shared/argocd/bootstrap` | Infisical secret path |
| `--local` | — | Force local kubernetes secret backend |
| `--ghcr-username <user>` | git user name | GitHub Container Registry username |
| `--ghcr-token <token>` | `$GITHUB_TOKEN` | GitHub Container Registry token |

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_TOKEN` | Recommended | Used as GHCR token if `--ghcr-token` is not set |
| `INFISICAL_UNIVERSAL_AUTH_CLIENT_ID` | When `--infisical-project` is set | Infisical Universal Auth client ID |
| `INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET` | When `--infisical-project` is set | Infisical Universal Auth client secret |
| `LINODE_TOKEN` | When `--external-dns` is set | Linode API token for DNS management |
| `NGROK_API_KEY` | When `--ngrok` is set | Ngrok API key |
| `NGROK_AUTHTOKEN` | When `--ngrok` is set | Ngrok auth token |
| `GCLOUD_K8S_RW_TOKEN` | kubernetes backend only | Grafana Cloud k8s read/write token |
| `GCLOUD_HOSTED_LOGS_ID` | kubernetes backend only | Grafana Cloud hosted logs instance ID |
| `GCLOUD_HOSTED_METRICS_ID` | kubernetes backend only | Grafana Cloud hosted metrics instance ID |

## Local Cluster Creation

### Docker Based Cluster (k3d)

Basically `k3s` but running on Docker. More lightweight and easier to stand up than a VM based cluster and generally preferrable for most local application development purposes. This should also be relatively portable to alternative Kubernetes providers:

```
./scripts/providers/k3d/create.sh 
```

### VM Based Cluster (k3s)

Start a development VM using `libvirt` on a Linux host. Useful when developing base images and cluster bootstrap scripts or to fully isolate the k8s control plane from the host operating system. Requires a functioning setup of [KVM, QEMU and libvirt](https://joshrosso.com/docs/2020/2020-05-06-linux-hypervisor-setup/).

On Fedora: 

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

### Cloud Based Clusters

- This tool is not designed to create cloud based clusters since there is too much variety between them
- The [bootstrapping](#bootstrapping) components however are still intended to work on managed clusters by major providers
- So far I tested this only for [Linode LKE](https://techdocs.akamai.com/cloud-computing/docs/linode-kubernetes-engine)
- See [cloud cluster bootstrap](#cloud-based-deployment) for instructions how to bootstrap an LKE cluster

## Bootstrapping

> [!WARNING]
> The default configuration will use whatever current `KUBECONFIG` and context are active. Use `--kubecfg` or `--context` to explicitly select a different context if needed.

This will install ArgoCD which will then bootstrap the cluster. This should be relatively cluster-agnostic. However, it has only been tested with k3d/k3s for now. The exact flags to pass into `bootstrap.sh` depend on the cluster connection details

### Preconditions

This assumes that you already have a cluster running and a working kubectl connection. Currently local development clusters like k3d or k3s and [Linode LKE](https://techdocs.akamai.com/cloud-computing/docs/linode-kubernetes-engine) based clusters are supported.

### Local Deployment

If you have a local k3d or k3s cluster running, it'll bootstrap that cluster. Set `--auto-sync` to enable auto sync for all ArgoCD applications:

```sh
./scripts/bootstrap.sh --auto-sync
```

The script will output instructions how to get the admin passwort and access the ArgoCD GUI.

Without `--auto-sync`, this will only install ArgoCD and sync the initial ArgoCD bootstrap application and its dependencies. You will need to manually sync each app. It can also be toggled on/off retroactively.

```sh
./scripts/bootstrap.sh 
```

### Cloud Based Deployment

To bootstrap a cluster into the cloud, only LKE is currently tested, although this should in principle also work with other managed clusters. It is up to the user to decide how to obtain a cluster in the first place and usually requires additional infrastructure. 

This repo has been tested for [zuse-cc/terraform-linode-lke-cluster](https://github.com/zuse-cc/terraform-linode-lke-cluster/), a matching Terraform version of this bootstrap script can be found [here](https://github.com/zuse-cc/terraform-helm-cluster-bootstrap)

```sh
./scripts/bootstrap.sh --auto-sync --domain my-cluster-l4b.dev.example.com --external-dns
```

### Validation

When external-dns is enabled, the default configuration will deploy a demo app and a DNS record for the endpoint should be created automatically. This means you can test the end-to-end deployment by validating that endpoint:

```sh
$ curl echo.my-cluster-l4b.dev.example.com
Hello, World!
```

For a local deployment this should work as well, but you may need to set up the host record in your local `/etc/hosts` first.

## Cluster Access

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

## Components

### Certificate Manager

The default `cert-manager` configuration uses a local, self signed root CA for all certificate requests in the cluster. LetsEncrypt is supported when [external dns](#external-dns) is enabled too. In that case a `--domain` and `--letsencrypt-email` need to be passed to the bootstrap script and a `LINODE_TOKEN` is required:

```sh
export LINODE_TOKEN=<your linode token> # Or use .env
./scripts/bootstrap.sh --auto-sync --external-dns --domain cluster.example.com --letsencrypt-email hostmaster@cluster.example.com
```

Cert manager will be using the `dns01` challenge so issuance of certificates can take a few minutes. Check the Linode console for the correct TXT records are being set in the clusters DNS zone. In the meantime, the Ingress controllers default dummy certificate will be shown.

To validate a certificate on a local cluster:

```sh
HOST=$(kubectl get ingress hello-world -n default -o jsonpath='{.spec.rules[*].host}')
IP=$(kubectl get ingress hello-world -n default -o jsonpath='{.status.loadBalancer.ingress[*].ip}')
openssl s_client -connect $IP:443 -servername $HOST | openssl x509 -text -noout | grep Issuer
```

### External Secrets

To create the cluster secret store required to bootstrap the cluster, credentials to access the [Infisical API](https://infisical.com/docs/documentation/platform/identities/universal-auth) are required. This requires the necessary credentials to be set in the shell or `.env` file:

```sh
INFISICAL_PROJECT_ID=some-secret-project
INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=...
INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=...
```

Secrets will be expected to reside under `/path/<cluster-name`, use `--name` to select the secret store to use:

```sh
./scripts/bootstrap.sh $(hostname)-k3d-lab --auto-sync --name my-dev-cluster
```

### External DNS

External DNS is supported for [Linode DNS Manager](https://techdocs.akamai.com/cloud-computing/docs/dns-manager) for now. Requires an existing Linode domain and a valid `LINODE_TOKEN`. The token can be either in an external secrets store or on the local shell environment. See [External Secrets](#external-secrets) 

```sh
export LINODE_TOKEN=<your linode token> # Or use .env
./scripts/bootstrap.sh --auto-sync --external-dns --domain your-domain.example.com
```

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
./scripts/bootstrap.sh $(hostname)-k3d-lab --ngrok
```

This [sample app](https://ngrok.com/docs/getting-started/kubernetes/ingress#3-deploy-a-sample-service) can be used to validate functionality.

**Important: Ngrok Resource Cleanup**

The ngrok operator uses a finaliser to clean up the Ngrok Operator resources registered in the backend. When destroying a cluster the finaliser may not be able to run and the operators in the [dashboard](https://dashboard.ngrok.com/kubernetes-operators) will get orphaned. We are intentionally _not_ attempting to clean them up as part of cluster deprovisioning [^1]. 

To periodically clean dangling endpoints (NB: This will delete ALL registered operators in your account [^2]): 

```
./scripts/misc/ngrok-cleanup.sh
```

## Additional Options

To set `--kubecfg` to the kubernetes config file created as part of cluster creation:

```sh
./scripts/bootstrap.sh --kubecfg $PWD/vms/k3s-lab/.kubecfg --auto-sync
```

To use the default `KUBECONFIG` but explicitly select a context:

```sh
./scripts/bootstrap.sh --context k3d-k3s-default --auto-sync
```

To deploy a specific branch or tag instead of `main`:

```sh
./scripts/bootstrap.sh --version my-working-branch
```

[^1]: Doing so would leak problematic behaviour of a 3rd party operator into our toolchain and create complex, brittle code to maintain. The long-term maintenance drag is ultimately not worth the short term convenience gained.

[^2]: Haven't found a way to label or tag the remote resources in any predictable way yet, so for now make sure to use a dedicated account for dev

