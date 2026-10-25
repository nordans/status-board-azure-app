output "resource_group_name" {
  description = "Resource group containing the development platform."
  value       = data.azurerm_resource_group.platform.name
}

output "aks_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "public_dns_label" {
  description = "Regional Azure public IP DNS label for the operator-managed application Gateway."
  value       = "${local.name}-${local.suffix}"
}

output "public_hostname" {
  description = "Expected application hostname after the public Gateway is provisioned."
  value       = "${local.name}-${local.suffix}.${var.location}.cloudapp.azure.com"
}

output "acr_login_server" {
  description = "Registry endpoint for application images."
  value       = module.registry.login_server
}

output "key_vault_name" {
  description = "Key Vault used for application secrets."
  value       = module.key_vault.name
}

output "workload_identity_client_id" {
  description = "Client ID for the Kubernetes service account annotation and CSI configuration."
  value       = module.workload_identity.client_id
}

output "tenant_id" {
  description = "Microsoft Entra tenant ID for the CSI configuration."
  value       = data.azurerm_client_config.current.tenant_id
}

output "kubernetes_namespace" {
  description = "Namespace required by the federated identity subject."
  value       = local.namespace
}

output "kubernetes_service_account" {
  description = "Service account required by the federated identity subject."
  value       = local.service_account
}
