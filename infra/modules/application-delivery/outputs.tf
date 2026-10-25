output "client_ids" {
  description = "Delivery client IDs to store as GitHub Actions secrets."
  value       = { for name, identity in azurerm_user_assigned_identity.github : name => identity.client_id }
}
