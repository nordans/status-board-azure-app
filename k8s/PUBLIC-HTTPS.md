# Public HTTPS

The public entry point uses the AKS-managed `approuting-istio` Gateway API implementation, an Azure Standard Load Balancer, an Azure public IP DNS label and cert-manager 1.21.3 with Let's Encrypt HTTP-01. No Helm installation, purchased domain, Azure DNS zone or additional node pool is required. Azure bills public IP, load balancer and traffic resources; gateway and certificate controllers consume capacity on the existing nodes.

Traffic follows `browser -> Azure Load Balancer -> HTTPS Gateway -> status-board Service:8000 -> application pod`. TLS terminates at the Gateway; the backend hop uses HTTP inside the cluster. The public endpoint exposes the dashboard and its API, including token-authenticated updates. The AKS management API keeps its existing IP allowlist.

The Gateway, Issuer, Certificate and HTTPRoutes live in `status-board-ingress`. A ReferenceGrant in `status-board` permits routes from that ingress namespace to reference only the application's named Service. Gateway listeners accept routes only from their own namespace. The application Service remains ClusterIP and its deployment identity gains no new permissions.

## Provision the cluster implementation

Merge the infrastructure configuration and run **Infrastructure deployment** from `main` with operation `deploy`. Review the saved plan and approve its apply through `dev-infra-apply`. The new AzAPI resource patches only the two ingress settings on the existing AKS resource. It does not recreate the cluster or change its API allowlist.

Use an authorized cluster operator and the isolated kubeconfig from [AKS prerequisites](README.md#aks-prerequisites). The commands below assume `terraform`, `kubectl`, Python and `kubelogin` are available and run from the repository root. Use the development root's initialized backend. Do not use the application delivery identity to install cluster-wide components.

```powershell
$publicDnsLabel = terraform -chdir=infra/environments/dev output -raw public_dns_label
$publicHostname = terraform -chdir=infra/environments/dev output -raw public_hostname
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=300s
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure wait --for=condition=Accepted gatewayclass/approuting-istio --timeout=300s
```

Let AKS install and update Gateway API CRDs. Do not install a second self-managed bundle or enable the Istio service mesh add-on alongside Application Routing.

## Install cert-manager

Prepare the official release manifest locally. The helper verifies its SHA-256 before writing it and adds the controller's Gateway API flag. The pinned checksum comes from the GitHub release asset digest. It does not contact Kubernetes or apply resources.

```powershell
uv run --locked python scripts/prepare_cert_manager.py --output-dir .cache/cert-manager
kubectl kustomize .cache/cert-manager --output .cache/cert-manager-rendered.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure apply --server-side --field-manager=status-board-cert-manager -f .cache/cert-manager-rendered.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace cert-manager rollout status deployment/cert-manager --timeout=300s
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace cert-manager rollout status deployment/cert-manager-webhook --timeout=300s
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace cert-manager rollout status deployment/cert-manager-cainjector --timeout=300s
```

The upstream installer grants cert-manager cluster-wide permissions needed for certificate lifecycle management. cert-manager stores the ACME account key and TLS private keys in Kubernetes Secrets. These are separate from the application token, which remains mounted from Key Vault without Secret synchronization. Protect cluster operator access; base64 Secret encoding is not encryption.

Upgrade by reviewing a supported release for the cluster's Kubernetes version, updating `VERSION` and `MANIFEST_SHA256` in `scripts/prepare_cert_manager.py`, preparing its manifests and applying them with the same field manager.

## Validate staging issuance

Keep `APP_PUBLIC_HOSTNAME` unset until production HTTPS verification passes. Render the staging configuration first:

```powershell
uv run --locked python scripts/render_aks.py public --public-dns-label $publicDnsLabel --public-hostname $publicHostname --output .cache/public-staging.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure apply --server-side --field-manager=status-board-public -f .cache/public-staging.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board-ingress wait --for=condition=Ready certificate/status-board-public --timeout=600s
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board-ingress get gateways,httproutes,certificates
Resolve-DnsName $publicHostname
```

AKS creates a Standard public frontend for the Gateway's generated LoadBalancer Service and applies its DNS label. The IP is managed by that Service's lifecycle; deleting/recreating the Gateway can change the IP. The regional DNS label remains the configured name while available. Do not attach this label to another resource. The HTTP listener redirects application paths to HTTPS. cert-manager creates a temporary exact-match HTTPRoute for `/.well-known/acme-challenge/<token>`; its higher match specificity takes precedence over the redirect. Port 80 must remain reachable for issuance and renewal.

The staging certificate is intentionally untrusted by browsers. Do not submit the application token or bypass browser certificate validation during this phase. A successful `Certificate Ready` establishes that issuance works, not that the production trust chain is ready.

If issuance fails, inspect `certificates`, `certificaterequests`, `orders`, `challenges`, `gateways`, `httproutes` and namespace events, then cert-manager controller logs. Check public DNS, listener status, available node capacity, solver pod admission and port 80 reachability. Do not repeatedly request production certificates while troubleshooting.

## Enable production HTTPS

```powershell
uv run --locked python scripts/render_aks.py public --public-dns-label $publicDnsLabel --public-hostname $publicHostname --acme-environment production --output .cache/public-production.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure apply --server-side --dry-run=server --field-manager=status-board-public -f .cache/public-production.yaml
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure apply --server-side --field-manager=status-board-public -f .cache/public-production.yaml
$certificateGeneration = kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board-ingress get certificate status-board-public -o jsonpath='{.metadata.generation}'
$generationCondition = '--for=jsonpath={.status.conditions[?(@.type=="Ready")].observedGeneration}=' + $certificateGeneration
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board-ingress wait $generationCondition certificate/status-board-public --timeout=600s
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board-ingress wait --for=condition=Ready certificate/status-board-public --timeout=600s
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board-ingress wait --for=condition=Programmed gateway/status-board-public --timeout=300s
$deployedVersion = kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure --namespace status-board get configmap status-board-config -o jsonpath='{.data.APP_VERSION}'
uv run --locked python -m scripts.verify_public_endpoint --hostname $publicHostname --expected-version $deployedVersion
gh variable set APP_PUBLIC_HOSTNAME --body $publicHostname
```

Staging and production use separate account and certificate Secret names. The verification command performs normal certificate-chain and hostname validation, checks the HTTP 301 redirect, HSTS, readiness and served commit, and sends no application token. After it succeeds, open `https://<public_hostname>` and use the application normally. The application deployment workflow uses the same verification after rollout whenever `APP_PUBLIC_HOSTNAME` is set.

cert-manager renews the certificate automatically. Keep the HTTP listener, Issuer, DNS label, account Secret, controller and solver access in place. Monitor Certificate readiness and expiration for any environment kept beyond this short demonstration. An ACME account contact email can be added to the Issuer if operational notifications are required.

## Remove public exposure

Unset the workflow variable, then remove only the public resources using the same hostname and ACME environment used during setup:

```powershell
gh variable delete APP_PUBLIC_HOSTNAME
kubectl --kubeconfig .cache/aks.kubeconfig --context status-board-azure delete -f .cache/public-production.yaml --ignore-not-found
```

Gateway deletion removes its generated Service and public frontend. Confirm that Azure has removed the application frontend/public IP before proceeding with platform teardown. The namespace deletion also removes staging and production certificate/account Secrets. Uninstall cert-manager only when no other workloads depend on it. Keep platform destruction on the existing reviewed `plan -destroy` followed by applying that exact saved plan; do not use a direct Terraform destroy command.

## References

- [AKS Application Routing Gateway API](https://learn.microsoft.com/en-us/azure/aks/app-routing-gateway-api)
- [Azure public IP DNS labels](https://learn.microsoft.com/en-us/azure/aks/static-ip)
- [cert-manager HTTP-01 Gateway solver](https://cert-manager.io/docs/configuration/acme/http01/)
- [cert-manager supported releases](https://cert-manager.io/docs/releases/)
