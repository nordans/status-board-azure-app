# Application delivery identities

Creates three GitHub OIDC managed identities for an existing AKS platform. Configure the GitHub environments with custom deployment branch policies allowing only `main` before applying this module. `dev-app-deploy` must require review with administrator bypass disabled.

| Identity | Trust | Access |
| --- | --- | --- |
| Publish | `dev-app-publish` | AcrPush and metadata Reader on one registry |
| Deploy | `dev-app-deploy` | User credentials on one AKS; explicit application data actions on one namespace |
| Network | `dev-app-deploy` | AKS read/write on one cluster; join its node subnet; assign its control plane identity |

Inputs are declared in [variables.tf](variables.tf); [outputs.tf](outputs.tf) exports the three client IDs. Store these IDs as Actions secrets. No client passwords are created.

The network role can change AKS configuration beyond its IP allowlist: Azure does not provide field-level RBAC for this update. It cannot delete the cluster, retrieve credentials or administer role assignments. Network and Deploy share a trusted environment and runner job, so separate identities provide scoped roles and audit attribution, not isolation from malicious deployment code.

AKS updates also validate linked subnet authorization, including updates that only change API authorized IP ranges. A separate custom role grants the network identity only `Microsoft.Network/virtualNetworks/subnets/join/action` on `node_subnet_id`. It grants no subnet read, write or delete permission and does not use Network Contributor. The delivery root resolves the existing platform node subnet; it does not create or modify it.

The same update requires `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action` on the user-assigned identity attached to the control plane. A separate custom role grants only that action on `control_plane_identity_id`; it grants no identity read, create, update, delete or federation management. The caller's linked assignment permission is separate from the control plane's existing Managed Identity Operator role on the kubelet identity. No caller access to the kubelet or application identity is added.

Deploy can modify application code and execute a smoke test in its pod. It must therefore be trusted with data available to that application, including its mounted token. It receives no direct Key Vault data role or Kubernetes Secret/RBAC administration. Namespace, ServiceAccount and SecretProviderClass are operator-managed prerequisites.

The registry must use RBAC Registry Permissions mode. AcrPush does not apply to ABAC-enabled registries. Migrate registry mode and all publisher/kubelet roles together if adopting ABAC later.


Monitored AKS writes require Log Analytics linked authorization even when managed identity ingestion and disabled local authentication are configured. Terraform Apply has `Microsoft.OperationalInsights/workspaces/sharedKeys/action` plus explicit ContainerInsights solution lifecycle actions in the workload group. The operator-managed delivery root separately grants the API network identity only workspace metadata read, `sharedKeys/action` and `Microsoft.OperationsManagement/solutions/write` on the exact Log Analytics workspace when monitoring is enabled. Publisher and application deployment identities receive no workspace grant. This action permits retrieving workspace keys; Terraform does not retrieve or export them, and the workspace rejects key-based authentication. Set `monitoring_enabled = false` in the delivery root when platform monitoring is disabled.
