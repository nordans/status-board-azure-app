# Azure infrastructure

Terraform provisions an AKS development platform. GitHub Actions plans and deploys infrastructure through OIDC. Application manifests and image publishing are managed separately.

| Configuration | Resources | State |
| --- | --- | --- |
| `bootstrap` | Resource groups, private state/plan storage, deployment identities and scoped roles | Local initially; migrate to the isolated bootstrap container |
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
| [github-oidc](modules/github-oidc/README.md) | Separate GitHub planning/deployment identities and constrained role delegation | `plan_client_id`, `apply_client_id` |

`environments/dev/main.tf` wires the subnet and registry into AKS, then the AKS issuer and vault into workload identity. `bootstrap/main.tf` owns the resource groups and calls `state-backend` and `github-oidc`. Names, network ranges and node settings are selected by the roots. Module READMEs link to typed input declarations and list outputs.

The roots retain `moved` blocks for resources extracted into modules. Existing state is migrated to the new addresses during the next plan/apply. Review any proposed resource replacement before applying.

## Requirements

- Terraform 1.17.x; CI uses 1.17.0.
- Azure CLI and an active subscription.
- AzureRM 5.11.x, resolved to 5.11.0 in each committed `.terraform.lock.hcl`.
- TFLint 0.65.0 and Docker for local static checks.
- A Microsoft Entra security group for cluster administrators.

Bootstrap requires permission to create resource groups, storage, managed identities, custom role definitions and role assignments, typically an authorized subscription Owner. The deployment workflow uses the custom platform role and conditional delegation created by bootstrap rather than subscription-wide administrative roles. Azure management roles alone do not grant Blob or Key Vault data access.

Register these resource providers once using an authorized subscription administrator: `Microsoft.Storage`, `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.ContainerService`, `Microsoft.ContainerRegistry`, `Microsoft.KeyVault` and `Microsoft.ManagedIdentity`. Provider auto-registration is disabled.

## Bootstrap

Run from the repository root. Authenticate and select the subscription:

```sh
az login
az account set --subscription <subscription-id>
```

Copy `infra/bootstrap/terraform.tfvars.example` to `infra/bootstrap/terraform.tfvars`. Replace the subscription ID, operator public IPv4 address and operator Entra object ID. Obtain the user object ID with `az ad signed-in-user show --query id -o tsv`. Obtain the exact OIDC repository prefix with `gh api repos/OWNER/REPOSITORY/actions/oidc/customization/sub --jq .sub_claim_prefix`; recent repositories use immutable owner/repository IDs. Set `github_oidc_subject_prefix` to that result.

Choose a region that permits resources for the subscription; a listed region may still reject new customer deployments. Use the same deployment `location` and `name_prefix` for bootstrap and development. If existing resource groups must keep their metadata region while new resources use a different region, set the optional `resource_group_location` in bootstrap to the existing group location.

```sh
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output backend
terraform -chdir=infra/bootstrap output bootstrap_backend
terraform -chdir=infra/bootstrap output github_variables
```

The storage firewall accepts only the listed operator IP addresses. Shared Key authentication and public Blob access are disabled. Bootstrap grants the named operator Storage Blob Data Contributor on this account; allow time for propagation. The three private containers are `bootstrap-state`, `tfstate` and `tfplans`. Pipeline identities have data roles only on the last two and cannot modify bootstrap state through Blob APIs. They can change storage account network settings, so those identities remain trusted backend administrators within that limited scope.

Copy `infra/bootstrap/backend.tf.example` to `infra/bootstrap/backend.tf`. Create an ignored `infra/bootstrap/backend.tfbackend` from the `bootstrap_backend` output, including `container_name = "bootstrap-state"`. Migrate the bootstrap state:

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

Review the saved plan before applying it. These commands create billable resources. Prefer the protected workflow below for routine deployments.

## GitHub deployment configuration

Create environments `dev-infra-plan` and `dev-infra-apply`. For both, select custom deployment branch policies and allow only the `main` branch. Configure `dev-infra-apply` to require a trusted reviewer and disable administrator bypass. A single-owner repository may allow that owner to approve their own dispatch; multi-user repositories should prevent self-review.

Set these repository Actions variables. IDs and configuration are variables, not client secrets:

| Variable | Value |
| --- | --- |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Active Azure tenant and subscription |
| `AZURE_PLAN_CLIENT_ID`, `AZURE_APPLY_CLIENT_ID` | Client IDs from bootstrap `github_variables` |
| `TF_STATE_RESOURCE_GROUP`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER`, `TF_PLAN_CONTAINER` | Values from bootstrap `github_variables` |
| `AZURE_LOCATION`, `TF_NAME_PREFIX` | Deployment region and project prefix |
| `AKS_KUBERNETES_VERSION`, `AKS_NODE_VM_SIZE` | Regionally supported version and VM SKU |
| `OPERATOR_IPV4_ADDRESSES` | JSON array of allowed public operator IPv4 addresses |
| `AKS_API_AUTHORIZED_CIDRS` | JSON array of allowed Kubernetes API IPv4 CIDRs |
| `AKS_ADMIN_GROUP_OBJECT_IDS` | JSON array of Entra administrator security group object IDs |

The administrator group must exist and contain the authorized operators. Pipeline deployment identities receive no directory group administration rights. Confirm VM family quota and total regional quota, including the extra surge node required for upgrades, before approving a cluster plan.

Once `infra-deploy.yml` is merged into `main`, run **Actions → Infrastructure deployment → Run workflow** on `main`:

1. Leave `apply` disabled for a plan-only run. No platform apply job is started.
2. Enable `apply` to create a plan, save it privately and request environment approval.
3. Review the plan in the job summary, including all deletions/replacements and the commit SHA. Approve `dev-infra-apply` only when it matches the intended change.
4. The apply job checks out the same commit, downloads the saved plan, verifies SHA256 and applies that exact file. Terraform rejects a saved plan if the state has changed in the meantime; rerun planning rather than bypassing that check.

Plan files are stored in private Blob Storage, not public-repository Actions artifacts. They can contain sensitive values and should be removed when no longer required; Blob soft delete retains deleted versions for the configured retention period. Terraform log and summary rendering masks provider-declared sensitive attributes, but resource names, IDs, IP allowlists and other ordinary configuration appear in the plan.

Each job exchanges its GitHub OIDC token for Azure access. `scripts/infra_backend_access.py` temporarily allows that runner's public IPv4 address on the backend firewall, waits for data-plane access and removes only its own added rule in an `always()` cleanup step. Existing allowlisted IPs or ranges are preserved. An abrupt runner loss can prevent cleanup; inspect storage network rules and remove orphaned runner IPs. Public IP rules do not support access from the same Azure region as the storage account; use a suitable runner network or private endpoint if that limitation applies.

Infrastructure deployments are serialized with cancellation disabled. Do not run a manual local apply concurrently with a workflow deployment. Azure Blob locking remains enabled, with a five-minute lock wait. The workflow never runs on pull requests and does not deploy application workloads or publish images.

## Access and secrets

AKS uses Entra authentication and Azure RBAC. Local cluster accounts are disabled. Its public API is limited to `aks_api_authorized_cidrs`; an empty list and `0.0.0.0/0` are rejected. Use normal user credentials rather than `az aks get-credentials --admin`. Client access also requires the appropriate AKS credential retrieval permission and kubelogin.

The cluster identity receives Network Contributor on its node subnet and Managed Identity Operator on the kubelet identity. The kubelet identity receives AcrPull on ACR. The application identity receives Key Vault Secrets User on its dedicated vault. It federates only with `system:serviceaccount:status-board:status-board` through the AKS OIDC issuer.

The Key Vault firewall allows the node subnet through a service endpoint and the configured operator IPs. Purge protection is enabled. Secret values are created outside Terraform by a separately authorized operator; this configuration neither creates nor reads them. The application token must use 32–512 URL-safe characters. The later Kubernetes deployment must use the exported identity, namespace and service account, and mount the Key Vault secret through Secrets Store CSI with alias `admin_api_token`. Set `ADMIN_API_TOKEN_FILE` to the mounted path. CSI rotation polling is set to two minutes; avoid a `subPath` mount to allow refreshed files.

ACR Basic uses its public authenticated endpoint with administrator credentials disabled. Key Vault and state storage also use public endpoints with firewall restrictions. This environment does not include private endpoints or a private AKS API. The infrastructure workflow uses controlled temporary backend firewall rules; OIDC authentication alone does not bypass a firewall.

The workflow sets `ARM_USE_OIDC=true`, `ARM_USE_AZUREAD=true`, `ARM_CLIENT_ID`, `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID`, and grants only deployment jobs `id-token: write`. The Apply identity's role-assignment condition permits only four application roles for service principals in the development resource group. The Plan identity has no platform write or RBAC-delegation role, but it does have state/plan Blob write and backend network write. Neither identity is a subscription Owner or an unrestricted RBAC Administrator. Neither receives bootstrap state data access or Key Vault secret data access directly.

## Validation

The `Infrastructure CI` workflow runs on every PR to `main`, push to `main` and manual dispatch. It has only `contents: read` permission and does not authenticate to Azure. Both roots and all seven child modules are independently initialized and validated. CI copies the development root lockfile into child module working directories before using `init -backend=false -lockfile=readonly`; the roots own committed provider selections. Provider changes require an intentional lockfile update. Lockfiles include Linux AMD64 and Windows AMD64 checksums.

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

The default configuration uses two Standard_D4s_v5 system nodes; override the SKU with `node_vm_size` or the workflow's `AKS_NODE_VM_SIZE` variable. It uses AKS Free control-plane tier, ACR Basic and locally redundant state storage. The system pool follows the [AKS minimum size requirements](https://learn.microsoft.com/en-us/azure/aks/use-system-pools). It has no multi-zone availability, application ingress, central log workspace or deployed workloads. Cilium enables network policy enforcement; workload policies belong with the application manifests. Application workloads will share this system pool in development; production workloads should use a separate user pool.

AKS Free does not make worker VMs, disks, load balancers, public IPs or registry storage free. Upgrades may temporarily add a surge node. Confirm costs and quota before applying. Stop the cluster when idle with `az aks stop --resource-group <resource-group> --name <aks-name>`; disks and other retained resources continue to incur charges. Resume it with `az aks start` before further changes.

State storage, its container and Key Vault use `prevent_destroy`. For permanent decommissioning, export required data, remove the applicable guards in a reviewed change, then inspect a destruction plan before applying. Key Vault purge protection prevents immediate purge for its seven-day retention period. Delete the platform before removing its bootstrap backend and resource group.
