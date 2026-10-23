output "storage_account_name" {
  description = "Storage account name for backend configuration."
  value       = azurerm_storage_account.state.name
}

output "container_name" {
  description = "Container name for backend configuration."
  value       = azurerm_storage_container.state.name
}

output "container_id" {
  description = "Container resource ID for data-plane role assignments."
  value       = azurerm_storage_container.state.id
}
