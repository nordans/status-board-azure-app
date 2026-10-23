data "azurerm_client_config" "current" {}

locals {
  name            = "${var.name_prefix}-dev"
  suffix          = substr(sha256("${var.subscription_id}:${local.name}"), 0, 8)
  namespace       = "status-board"
  service_account = "status-board"
  tags = {
    application = "status-board"
    environment = "dev"
    managed_by  = "terraform"
  }
}

data "azurerm_resource_group" "platform" {
  name = "rg-${local.name}"
}

resource "azurerm_virtual_network" "platform" {
  name                = "vnet-${local.name}"
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location
  address_space       = ["10.42.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "aks-nodes"
  resource_group_name  = data.azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = ["10.42.0.0/24"]

  service_endpoint {
    service = "Microsoft.KeyVault"
  }
}

resource "azurerm_container_registry" "app" {
  name                = "${var.name_prefix}dev${local.suffix}"
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_key_vault" "app" {
  name                          = "kv-${var.name_prefix}-${local.suffix}"
  resource_group_name           = data.azurerm_resource_group.platform.name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = local.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "None"
    ip_rules                   = var.operator_ipv4_addresses
    virtual_network_subnet_ids = [azurerm_subnet.nodes.id]
  }

  lifecycle {
    prevent_destroy = true
  }
}
