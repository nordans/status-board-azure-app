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

output "storage_account_id" {
  description = "Storage account resource ID for scoped network administration."
  value       = azurerm_storage_account.state.id
}

output "bootstrap_container_name" {
  description = "Isolated bootstrap state container, unavailable to deployment identities."
  value       = azurerm_storage_container.bootstrap.name
}

output "plan_container_id" {
  description = "Private container scope for saved deployment plans."
  value       = azurerm_storage_container.plans.id
}

output "plan_container_name" {
  description = "Private container name for saved deployment plans."
  value       = azurerm_storage_container.plans.name
}
