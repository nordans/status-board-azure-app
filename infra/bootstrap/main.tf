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
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-${var.name_prefix}-dev"
  location = var.location
  tags = merge(local.tags, {
    environment = "dev"
  })
}

module "state_backend" {
  source                  = "../modules/state-backend"
  name                    = "st${var.name_prefix}tf${local.suffix}"
  resource_group_name     = azurerm_resource_group.state.name
  location                = azurerm_resource_group.state.location
  operator_ipv4_addresses = var.operator_ipv4_addresses
  tags                    = local.tags
}
