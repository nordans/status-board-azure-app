# aks

Creates AKS with dedicated control-plane and kubelet identities, subnet permissions and AcrPull. Entra RBAC, API allowlists, Cilium, Workload Identity and the Key Vault CSI provider are enabled. Backend and provider authentication remain the root configuration responsibility.

Inputs: `name`, `name_prefix`, `tenant_id`, `subnet_id`, `registry_id`, `kubernetes_version`, `node_vm_size`, `node_count`, `api_authorized_cidrs`, `admin_group_object_ids`, `pod_cidr`, `service_cidr`, `dns_service_ip`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `id`, `name`, `oidc_issuer_url`.

The module inherits AzureRM and AzAPI from its caller. AzAPI manages only `ingressProfile.gatewayAPI` and `ingressProfile.webAppRouting.gatewayAPIImplementations` on the existing cluster, enabling managed Gateway API CRDs and the `approuting-istio` implementation. AzureRM 5.11 does not expose these fields. No NGINX controller or application sidecar injection is enabled.

The update does not create a public application listener. Operator-managed Gateway manifests are described in [public HTTPS operations](../../../k8s/PUBLIC-HTTPS.md). Removing the AzAPI update from Terraform state does not disable the cluster feature; remove Gateway resources before disabling the implementation. Destroying the development cluster removes the implementation with it.

See [infrastructure operations](../../README.md) for backend setup and validation.
