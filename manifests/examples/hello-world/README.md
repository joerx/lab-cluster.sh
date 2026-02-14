Kubernetes Hello World

This example deploys a simple HTTP echo application and exposes it via a Service and an Ingress.

Manifests:

- `deployment.yaml` — Deployment using `hashicorp/http-echo:0.2.3` (responds with "Hello, World!")
- `service.yaml` — Service exposing the app on port 80
- `ingress.yaml` — Ingress routing `hello.local` to the Service (Ingress class `nginx`)

Apply all manifests:

```bash
kubectl apply -f .
```

Test (replace <INGRESS-IP> with your Ingress controller address):

```bash
curl -H "Host: hello.local" http://<INGRESS-IP>/
```

If you're running locally (kind/minikube), add an entry in `/etc/hosts` mapping `hello.local` to the ingress IP.
