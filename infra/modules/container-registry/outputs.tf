output "id" {
  description = "Registry resource ID for scoped role assignments."
  value       = azurerm_container_registry.app.id
}

output "login_server" {
  description = "Authenticated registry endpoint."
  value       = azurerm_container_registry.app.login_server
}
