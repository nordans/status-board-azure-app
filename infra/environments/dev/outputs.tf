output "resource_group_name" {
  description = "Resource group containing the development platform."
  value       = data.azurerm_resource_group.platform.name
}

output "aks_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.platform.name
}

output "acr_login_server" {
  description = "Registry endpoint for application images."
  value       = azurerm_container_registry.app.login_server
}

output "key_vault_name" {
  description = "Key Vault used for application secrets."
  value       = azurerm_key_vault.app.name
}

output "workload_identity_client_id" {
  description = "Client ID for the Kubernetes service account annotation and CSI configuration."
  value       = azurerm_user_assigned_identity.app.client_id
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
