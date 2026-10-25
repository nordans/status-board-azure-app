# Azure infrastructure

Terraform provisions an AKS development platform. Application manifests, image publishing and deployment workflows are managed separately.

| Configuration | Resources | State |
| --- | --- | --- |
| `bootstrap` | State resource group, Storage Account, private Blob container and development resource group | Local initially; migrate to Blob after provisioning |
| `environments/dev` | VNet, node subnet, AKS, ACR, Key Vault, managed identities, workload federation and role assignments | Azure Blob |

## Modules

Root configurations select environment settings, configure the provider and backend, and connect modules through their outputs. Child modules inherit the provider and declare their own inputs and outputs.

| Module | Responsibility | Outputs used by callers |
| --- | --- | --- |
| [network](modules/network/README.md) | VNet and node subnet with the Key Vault service endpoint | `node_subnet_id` |
| [container-registry](modules/container-registry/README.md) | Authenticated image registry | `id`, `login_server` |
| [key-vault](modules/key-vault/README.md) | Vault, network allowlist and recovery settings | `id`, `name` |
| [aks](modules/aks/README.md) | Cluster, control-plane and kubelet identities, and their scoped roles | `name`, `oidc_issuer_url` |
| [workload-identity](modules/workload-identity/README.md) | Service account federation and read-only vault access | `client_id` |
| [state-backend](modules/state-backend/README.md) | Protected state storage and Blob container | `storage_account_name`, `container_name`, `container_id` |

`environments/dev/main.tf` wires the subnet and registry into AKS, then the AKS issuer and vault into workload identity. `bootstrap/main.tf` owns the resource groups and calls `state-backend`. Names, network ranges and node settings are selected by the roots. Module READMEs link to typed input declarations and list outputs.

The roots retain `moved` blocks for resources extracted into modules. Existing state is migrated to the new addresses during the next plan/apply. Review any proposed resource replacement before applying.

## Requirements

- Terraform 1.17.x; CI uses 1.17.0.
- Azure CLI and an active subscription.
- AzureRM 5.11.x, resolved to 5.11.0 in each committed `.terraform.lock.hcl`.
- TFLint 0.65.0 and Docker for local static checks.
- A Microsoft Entra security group for cluster administrators.

Bootstrap requires permission to create resource groups and storage resources. Platform provisioning requires Contributor and permission to assign roles within the development resource group, such as Role Based Access Control Administrator. Backend readers and writers need Storage Blob Data Contributor on the state container. Azure management roles alone do not grant Blob or Key Vault data access.

Register these resource providers once using an authorized subscription administrator: `Microsoft.Storage`, `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.ContainerService`, `Microsoft.ContainerRegistry`, `Microsoft.KeyVault` and `Microsoft.ManagedIdentity`. Provider auto-registration is disabled.

## Bootstrap

Run from the repository root. Authenticate and select the subscription:

```sh
az login
az account set --subscription <subscription-id>
```

Copy `infra/bootstrap/terraform.tfvars.example` to `infra/bootstrap/terraform.tfvars`. Replace the example subscription ID and public operator IPv4 address. Set `location` and `name_prefix` consistently in both configurations.

```sh
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output backend
```

The storage firewall accepts only the listed operator IP addresses. Shared Key authentication and public Blob access are disabled. Grant the operator Storage Blob Data Contributor on the container scope returned by `terraform output state_container_scope`; allow time for role propagation.

Copy `infra/bootstrap/backend.tf.example` to `infra/bootstrap/backend.tf`. Create an ignored `infra/bootstrap/backend.tfbackend` containing the backend output, using `key = "bootstrap.terraform.tfstate"`. Migrate the bootstrap state:

```sh
terraform -chdir=infra/bootstrap init -migrate-state -backend-config=backend.tfbackend
terraform -chdir=infra/bootstrap plan
```

Confirm that the state is present in Blob Storage and the plan is unchanged. Keep any local state backups in access-controlled encrypted storage. State files and saved plans can contain sensitive infrastructure data; they are excluded from Git.

## Development platform

Copy `infra/environments/dev/terraform.tfvars.example` to `infra/environments/dev/terraform.tfvars`. Replace all example values, including the administrator group object ID and IP allowlists. Use a supported AKS minor version and verify regional VM availability and subscription quota:

```sh
az aks get-versions --location westeurope --output table
az vm list-skus --location westeurope --size Standard_D4s_v5 --all --output table
az vm list-usage --location westeurope --output table
```

The example Kubernetes version is illustrative. The selected minor version receives automatic patch upgrades; node images use the `NodeImage` upgrade channel.

Copy `infra/environments/dev/backend.tfbackend.example` to `infra/environments/dev/backend.tfbackend` and fill in the bootstrap output. Keep the key `dev.terraform.tfstate` separate from bootstrap state.

```sh
terraform -chdir=infra/environments/dev init -backend-config=backend.tfbackend
terraform -chdir=infra/environments/dev plan -out=dev.tfplan
terraform -chdir=infra/environments/dev apply dev.tfplan
terraform -chdir=infra/environments/dev output
```

Review the saved plan before applying it. These commands create billable resources. No deployment workflow runs them automatically.

## Access and secrets

AKS uses Entra authentication and Azure RBAC. Local cluster accounts are disabled. Its public API is limited to `aks_api_authorized_cidrs`; an empty list and `0.0.0.0/0` are rejected. Use normal user credentials rather than `az aks get-credentials --admin`. Client access also requires the appropriate AKS credential retrieval permission and kubelogin.

The cluster identity receives Network Contributor on its node subnet and Managed Identity Operator on the kubelet identity. The kubelet identity receives AcrPull on ACR. The application identity receives Key Vault Secrets User on its dedicated vault. It federates only with `system:serviceaccount:status-board:status-board` through the AKS OIDC issuer.

The Key Vault firewall allows the node subnet through a service endpoint and the configured operator IPs. Purge protection is enabled. Secret values are created outside Terraform by a separately authorized operator; this configuration neither creates nor reads them. The application token must use 32–512 URL-safe characters. The later Kubernetes deployment must use the exported identity, namespace and service account, and mount the Key Vault secret through Secrets Store CSI with alias `admin_api_token`. Set `ADMIN_API_TOKEN_FILE` to the mounted path. CSI rotation polling is set to two minutes; avoid a `subPath` mount to allow refreshed files.

ACR Basic uses its public authenticated endpoint with administrator credentials disabled. Key Vault and state storage also use public endpoints with firewall restrictions. This environment does not include private endpoints or a private AKS API. A future hosted deployment runner will need an explicitly approved network path; OIDC authentication alone does not bypass these firewalls.

For automated Terraform access, set `ARM_USE_OIDC=true`, `ARM_USE_AZUREAD=true`, `ARM_CLIENT_ID`, `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID`, and grant the workflow `id-token: write`. Create a separate federated deployment identity scoped to the development resource group and state container. No client secret or application token is needed by infrastructure CI.

## Validation

The `Infrastructure CI` workflow runs on every PR to `main`, push to `main` and manual dispatch. It has only `contents: read` permission and does not authenticate to Azure. Both roots and all six child modules are independently initialized and validated. CI copies the development root lockfile into child module working directories before using `init -backend=false -lockfile=readonly`; the roots own committed provider selections. Provider changes require an intentional lockfile update. Lockfiles include Linux AMD64 and Windows AMD64 checksums.

```sh
terraform fmt -check -recursive infra
for module in infra/modules/*; do
  cp infra/environments/dev/.terraform.lock.hcl "$module/.terraform.lock.hcl"
done
for root in infra/bootstrap infra/environments/dev infra/modules/*; do
  terraform -chdir="$root" init -backend=false -lockfile=readonly
  terraform -chdir="$root" validate
  terraform -chdir="$root" test
done
tflint --init --config "$PWD/infra/.tflint.hcl"
tflint --recursive --chdir=infra --config "$PWD/infra/.tflint.hcl"
docker run --rm --volume "${PWD}:/repo:ro" --workdir /repo aquasec/trivy@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c config --severity HIGH,CRITICAL --exit-code 1 --ignorefile infra/.trivyignore.yaml infra
```

The validation block above uses a POSIX shell. Terraform tests mock Azure: module tests check authentication, network restrictions, scoped role assignments, recovery settings and invalid inputs; root tests check the environment contracts and input validation. They do not prove quota, regional availability or successful Azure provisioning. A real authenticated plan and deployment remain required.

The scoped Trivy exception in `.trivyignore.yaml` keeps trusted-service firewall bypass disabled on state storage. It applies only to the storage rule in `modules/state-backend/main.tf`, carries a justification and expires on 2027-01-31. Other high and critical findings fail CI. Trivy downloads current checks when scanning.

## Operations

This environment uses two Standard_D4s_v5 system nodes, AKS Free control-plane tier, ACR Basic and locally redundant state storage. The system pool follows the [AKS minimum size requirements](https://learn.microsoft.com/en-us/azure/aks/use-system-pools). It has no multi-zone availability, application ingress, central log workspace or deployed workloads. Cilium enables network policy enforcement; workload policies belong with the application manifests. Application workloads will share this system pool in development; production workloads should use a separate user pool.

AKS Free does not make worker VMs, disks, load balancers, public IPs or registry storage free. Upgrades may temporarily add a surge node. Confirm costs and quota before applying. Stop the cluster when idle with `az aks stop --resource-group <resource-group> --name <aks-name>`; disks and other retained resources continue to incur charges. Resume it with `az aks start` before further changes.

State storage, its container and Key Vault use `prevent_destroy`. For permanent decommissioning, export required data, remove the applicable guards in a reviewed change, then inspect a destruction plan before applying. Key Vault purge protection prevents immediate purge for its seven-day retention period. Delete the platform before removing its bootstrap backend and resource group.
