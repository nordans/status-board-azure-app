# Kubernetes deployment

The manifests run Status Board with one replica, a ClusterIP Service, a ConfigMap and a dedicated ServiceAccount. The `base` directory contains shared resources; `overlays/local` selects a locally loaded image and local environment settings. Kustomize is built into `kubectl`; no Helm installation is required.

## Local requirements

- Docker Desktop running Linux containers.
- Minikube 1.39.x and kubectl 1.36.x.
- Available resources for a two-CPU, 3-GiB local cluster.

Run these commands from the repository root. The dedicated profile avoids using another cluster from the current kubeconfig context:

```powershell
minikube start --profile status-board --driver=docker --cpus=2 --memory=3072 --kubernetes-version=v1.36.5 --keep-context
kubectl --context=status-board get nodes
docker build --target runtime --tag status-board:local-k8s .
minikube --profile status-board image load status-board:local-k8s
```

Create the local token file and namespace, then store the token in a Kubernetes Secret:

```powershell
uv run --locked python scripts/new_local_secret.py
kubectl --context=status-board apply -f k8s/base/namespace.yaml
kubectl --context=status-board --namespace=status-board create secret generic status-board-admin --from-file=admin_api_token=.secrets/admin_api_token --dry-run=client -o yaml | kubectl --context=status-board --namespace=status-board apply -f -
```

The token file is ignored by Git and excluded from the image. Kubernetes Secret values are base64-encoded data, not inherently encrypted by the manifest. This local setup is intended for development; the AKS deployment will mount the application token from Azure Key Vault through Secrets Store CSI.

Review and apply the local configuration:

```powershell
kubectl kustomize k8s/overlays/local
kubectl --context=status-board apply --dry-run=server -k k8s/overlays/local
kubectl --context=status-board apply -k k8s/overlays/local
kubectl --context=status-board --namespace=status-board rollout status deployment/status-board --timeout=180s
kubectl --context=status-board --namespace=status-board get pods,services
```

Forward the service in a separate terminal:

```powershell
kubectl --context=status-board --namespace=status-board port-forward service/status-board 18000:8000 --address=127.0.0.1
```

Open `http://127.0.0.1:18000`. In another terminal, run the application smoke test:

```powershell
uv run --locked python scripts/smoke_test.py --base-url http://127.0.0.1:18000
kubectl --context=status-board --namespace=status-board exec deployment/status-board -- id
```

The smoke test writes a report to the first configured service. Use it only against a test environment. Kubernetes probes separately check startup, readiness and liveness. A missing or invalid token removes the pod from service through readiness; liveness checks only whether the process can serve HTTP.

## Runtime behavior

The process runs as UID/GID 10001 with a read-only root filesystem, no added Linux capabilities and no privilege escalation. Seccomp uses the runtime default. A size-limited, memory-backed `/tmp` is the only writable mount. The namespace enforces the restricted Pod Security Standard, and the application does not mount a Kubernetes API token.

The application stores reports in process memory. Keep one replica and one worker. The Deployment uses `Recreate` to avoid concurrently serving independent in-memory boards during updates; updates interrupt service and reset reports. Add shared storage before increasing replicas or requiring availability during deployments.

The token volume is mounted as a directory without `subPath`, allowing Secret volume updates to become visible. ConfigMap values are environment variables, so a configuration change requires a restart. After rebuilding and loading the local image or changing environment configuration:

```powershell
kubectl --context=status-board --namespace=status-board rollout restart deployment/status-board
kubectl --context=status-board --namespace=status-board rollout status deployment/status-board --timeout=180s
```

Keep the port-forward running only while accessing the application. Stop the local cluster when finished:

```powershell
minikube stop --profile status-board
```

## Validation

The infrastructure workflow scans these manifests with Trivy. Use server-side dry-run and rollout checks against the local cluster to verify Kubernetes API validation and runtime behavior. A successful local deployment does not verify Azure networking, ACR authorization or Key Vault Workload Identity.
