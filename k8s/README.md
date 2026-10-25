# Kubernetes deployment

The manifests run Status Board with one replica, a ClusterIP Service, a ConfigMap and a dedicated ServiceAccount. The `base` directory contains shared resources; `overlays/local` selects a locally loaded image and local environment settings. Kustomize is built into `kubectl`; no Helm installation is required.

For Azure, `bootstrap/aks` contains operator-managed namespace, ServiceAccount and SecretProviderClass resources. `overlays/aks` contains only the application ConfigMap, Service and Deployment, using an ACR image digest and a read-only Key Vault CSI volume. This separation keeps namespace and workload identity configuration outside routine application deployment permissions.

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

## AKS prerequisites

Provision the [development platform](../infra/README.md) and [delivery access](../infra/delivery/README.md). Use an authorized cluster administrator from the configured Entra group. Install kubectl 1.36.x and kubelogin 0.2.22. Keep the operator public IP on the AKS API and Key Vault allowlists.

Create the Key Vault secret `status-board-admin-token` using an authorized secret operator and a local file containing a 32–512-character URL-safe token. Keep the file outside Git, for example `.secrets/azure_admin_api_token`. Do not print the token or pass its value as a command-line argument:

```powershell
az keyvault secret set --vault-name "<vault-name>" --name status-board-admin-token --file .secrets/azure_admin_api_token --encoding utf-8 --only-show-errors -o none
```

The secret operator needs a scoped data role such as Key Vault Secrets Officer; subscription Owner alone does not grant data access. Remove temporary operator grants after provisioning. The application workload identity already has Key Vault Secrets User from the development Terraform configuration. Delivery identities receive no direct Key Vault data role.

Run the following from the repository root after initializing the development Terraform backend. The commands use an isolated kubeconfig and explicit context:

```powershell
New-Item -ItemType Directory -Force .cache | Out-Null
$clusterName = terraform -chdir=infra/environments/dev output -raw aks_name
$resourceGroup = terraform -chdir=infra/environments/dev output -raw resource_group_name
$workloadClientId = terraform -chdir=infra/environments/dev output -raw workload_identity_client_id
$tenantId = terraform -chdir=infra/environments/dev output -raw tenant_id
$vaultName = terraform -chdir=infra/environments/dev output -raw key_vault_name
az aks get-credentials --resource-group $resourceGroup --name $clusterName --file .cache/aks.kubeconfig --context status-board-azure
kubelogin convert-kubeconfig --login azurecli --kubeconfig .cache/aks.kubeconfig
uv run --locked python scripts/render_aks.py bootstrap --app-client-id $workloadClientId --tenant-id $tenantId --key-vault-name $vaultName --output .cache/aks-bootstrap.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure apply --server-side --field-manager=status-board-bootstrap -f .cache/aks-bootstrap.yaml
```

The CSI configuration mounts the secret as `/mnt/secrets-store/admin_api_token` with file permissions `0444` in a read-only volume mounted only in the application container. The AKS overlay sets `ADMIN_API_TOKEN_FILE` to that path. Keeping this mount outside `/run/secrets` avoids masking Workload Identity's projected token at `/var/run/secrets/azure/tokens` on images where `/var/run` points to `/run`. The file mode permits UID 10001 to read it without relying on CSI ownership changes; the managed AKS driver's `ReadWriteOnceWithFSType` policy does not guarantee filesystem-group handling for inline volumes. The token is not synchronized into a Kubernetes Secret. Workload Identity adds its own projected Azure-audience token; automatic mounting of the default Kubernetes API token remains disabled. CSI rotation is enabled on the cluster and the application reads the token file when authorizing requests. Test rotation against the running AKS workload before relying on its timing.

## Application deployment workflow

After the prerequisites are complete and the workflow is merged, select **Actions → Application deployment → Run workflow → main**. Other branches skip all delivery jobs and are rejected by the GitHub environments' branch policies. The workflow runs only on manual dispatch; ordinary PRs and pushes retain the lightweight CI behavior.

The workflow reuses Python CI, builds one image, tests that image with a generated test token, reports HIGH/CRITICAL image vulnerabilities, and blocks publication when any such finding has an available fix. Unfixed findings remain visible in the report and do not block this development pipeline. The full image report is in the job log; this gate does not establish that the image has no known vulnerabilities. Infrastructure misconfiguration scanning and the Python dependency audit retain their existing blocking policies.

Only after testing does the publication identity sign in through GitHub OIDC, push the commit-tagged image to ACR and record its digest in the job summary. Review this commit and digest before approving `dev-app-deploy`. The deployment job uses that digest without rebuilding the image.

The job temporarily adds its own public `/32` to the existing AKS API allowlist, switches from the network identity to the namespace deployment identity, obtains user credentials and waits for API authorization. It renders the application manifests, performs a server-side dry run, applies them and waits for readiness. Its final smoke test executes inside the application pod against `http://status-board:8000`, testing the ClusterIP Service, health, public reads, rejected unauthenticated writes and authenticated writes. The real token is read inside the pod and is not returned to the runner. The test updates the first service report in this development environment.

Application and infrastructure workflows share the same concurrency group with cancellation disabled. Temporary access cleanup runs on success or failure, re-reads the current allowlist and removes only the rule recorded as added by that job. Existing IP ranges and changes made before cleanup's read are preserved. Cleanup refuses to clear the last rule. Abrupt runner loss or a failed cleanup still requires operator intervention; inspect the recorded runner rule and restore the allowlist before further Terraform runs. Do not run local infrastructure changes concurrently with deployment.

The network role permits changes to the whole AKS configuration at that one resource scope; Azure does not restrict it to just the allowlist field. Network and deployment identities share the protected deployment job and are not a security boundary against malicious code in that job. Deployers can change application code and execute in its pod, so they are trusted with application data even without direct Secret or Key Vault read permissions.

The Service remains ClusterIP. Use an operator port-forward with the isolated kubeconfig to access the demonstration; no public ingress is created. This application has one replica and uses Recreate, so deployment interrupts service and resets its in-memory reports.

For recovery, use a previously verified image digest and its corresponding commit with `scripts/render_aks.py application`, then review and apply the rendered file as an authorized operator. A rollback must update the ConfigMap version and Deployment together; it cannot restore in-memory reports. Failed rollout or smoke tests fail the workflow without silently switching to another image.
