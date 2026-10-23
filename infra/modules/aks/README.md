# aks

Creates AKS with dedicated control-plane and kubelet identities, subnet permissions and AcrPull. Entra RBAC, API allowlists, Cilium, Workload Identity and the Key Vault CSI provider are enabled. Backend and provider authentication remain the root configuration responsibility.

Inputs: `name`, `name_prefix`, `tenant_id`, `subnet_id`, `registry_id`, `kubernetes_version`, `node_vm_size`, `node_count`, `api_authorized_cidrs`, `admin_group_object_ids`, `pod_cidr`, `service_cidr`, `dns_service_ip`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `id`, `name`, `oidc_issuer_url`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
