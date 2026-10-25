output "plan_client_id" {
  description = "Client ID trusted by the dev-infra-plan environment."
  value       = azurerm_user_assigned_identity.github["plan"].client_id
}

output "apply_client_id" {
  description = "Client ID trusted by the dev-infra-apply environment."
  value       = azurerm_user_assigned_identity.github["apply"].client_id
}
