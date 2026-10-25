locals {
  suffix = substr(sha256("${var.subscription_id}:${var.name_prefix}:tfstate"), 0, 8)
  tags = {
    application = "status-board"
    environment = "management"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = coalesce(var.resource_group_location, var.location)
  tags     = local.tags
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-${var.name_prefix}-dev"
  location = coalesce(var.resource_group_location, var.location)
  tags = merge(local.tags, {
    environment = "dev"
  })
}

module "state_backend" {
  source                  = "../modules/state-backend"
  name                    = "st${var.name_prefix}tf${local.suffix}"
  resource_group_name     = azurerm_resource_group.state.name
  location                = var.location
  operator_ipv4_addresses = var.operator_ipv4_addresses
  tags                    = local.tags
}

resource "azurerm_role_assignment" "bootstrap_operator" {
  scope                = module.state_backend.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.bootstrap_operator_object_id
  principal_type       = "User"
}

module "github_oidc" {
  source                     = "../modules/github-oidc"
  name_prefix                = var.name_prefix
  resource_group_name        = azurerm_resource_group.state.name
  location                   = var.location
  tags                       = local.tags
  github_oidc_subject_prefix = var.github_oidc_subject_prefix
  workload_resource_group_id = azurerm_resource_group.workload.id
  state_resource_group_id    = azurerm_resource_group.state.id
  storage_account_id         = module.state_backend.storage_account_id
  state_container_id         = module.state_backend.container_id
  plan_container_id          = module.state_backend.plan_container_id
}
