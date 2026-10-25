# github-oidc

Creates separate planning and deployment managed identities for GitHub environments `dev-infra-plan` and `dev-infra-apply`.

The planning identity receives Reader and the AKS Cluster User role on the development resource group. The deployment identity receives a custom role limited to the resource types used by the platform. A separate conditional role assignment allows delegating only Network Contributor, Managed Identity Operator, AcrPull and Key Vault Secrets User to service principals within that group. The deployment identity cannot change role definitions or grant Owner, Contributor or RBAC administrator roles.

Both identities receive Blob Data Contributor on the development state and private plan containers. Bootstrap state uses a separate container with no pipeline data role. A custom account-scoped role permits storage account read/write for temporary firewall rules, excluding deletion and key-listing. Storage account write can change other account settings; this permission is required by the public runner network model.

Inputs and their scopes are declared in `variables.tf`. `github_oidc_subject_prefix` must match the exact repository prefix returned by `gh api repos/OWNER/REPOSITORY/actions/oidc/customization/sub`. GitHub environment branch restrictions and required reviewers must be configured separately before enabling the workflow.

Outputs: `plan_client_id`, `apply_client_id`. The module inherits AzureRM authentication from its root. See [deployment operations](../../README.md).
