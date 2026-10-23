output "id" {
  description = "Vault resource ID for scoped role assignments."
  value       = azurerm_key_vault.app.id
}

output "name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.app.name
}
