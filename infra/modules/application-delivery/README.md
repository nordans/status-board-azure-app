# Application delivery identities

Creates three GitHub OIDC managed identities for an existing AKS platform. Configure the GitHub environments with custom deployment branch policies allowing only `main` before applying this module. `dev-app-deploy` must require review with administrator bypass disabled.

| Identity | Trust | Access |
| --- | --- | --- |
| Publish | `dev-app-publish` | AcrPush and metadata Reader on one registry |
| Deploy | `dev-app-deploy` | User credentials on one AKS; explicit application data actions on one namespace |
| Network | `dev-app-deploy` | AKS read/write on one cluster |

Inputs are declared in [variables.tf](variables.tf); [outputs.tf](outputs.tf) exports the three client IDs. Store these IDs as Actions secrets. No client passwords are created.

The network role can change AKS configuration beyond its IP allowlist: Azure does not provide field-level RBAC for this update. It cannot delete the cluster, retrieve credentials or administer role assignments. Network and Deploy share a trusted environment and runner job, so separate identities provide scoped roles and audit attribution, not isolation from malicious deployment code.

Deploy can modify application code and execute a smoke test in its pod. It must therefore be trusted with data available to that application, including its mounted token. It receives no direct Key Vault data role or Kubernetes Secret/RBAC administration. Namespace, ServiceAccount and SecretProviderClass are operator-managed prerequisites.

The registry must use RBAC Registry Permissions mode. AcrPush does not apply to ABAC-enabled registries. Migrate registry mode and all publisher/kubelet roles together if adopting ABAC later.
