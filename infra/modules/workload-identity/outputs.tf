output "client_id" {
  description = "Client ID for the service account annotation and CSI configuration."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "principal_id" {
  description = "Managed identity service principal object ID."
  value       = azurerm_user_assigned_identity.app.principal_id
}
