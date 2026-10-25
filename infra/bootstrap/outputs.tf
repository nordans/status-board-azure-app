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

output "bootstrap_backend" {
  description = "Backend configuration for migrating bootstrap state into its isolated container."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = module.state_backend.storage_account_name
    container_name       = module.state_backend.bootstrap_container_name
    key                  = "bootstrap.terraform.tfstate"
  }
}

output "github_variables" {
  description = "Repository configuration for the deployment workflow; store client IDs as Actions secrets."
  value = {
    AZURE_PLAN_CLIENT_ID     = module.github_oidc.plan_client_id
    AZURE_APPLY_CLIENT_ID    = module.github_oidc.apply_client_id
    TF_STATE_RESOURCE_GROUP  = azurerm_resource_group.state.name
    TF_STATE_STORAGE_ACCOUNT = module.state_backend.storage_account_name
    TF_STATE_CONTAINER       = module.state_backend.container_name
    TF_PLAN_CONTAINER        = module.state_backend.plan_container_name
  }
}
