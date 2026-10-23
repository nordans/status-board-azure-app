output "backend" {
  description = "Azure Blob backend configuration for the development environment."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = module.state_backend.storage_account_name
    container_name       = module.state_backend.container_name
    key                  = "dev.terraform.tfstate"
  }
}

output "state_container_scope" {
  description = "Scope for the deployment identity's Storage Blob Data Contributor role."
  value       = module.state_backend.container_id
}

output "workload_resource_group_id" {
  description = "Scope for infrastructure deployment permissions."
  value       = azurerm_resource_group.workload.id
}
