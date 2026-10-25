resource "azurerm_key_vault" "app" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = var.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "None"
    ip_rules                   = var.operator_ipv4_addresses
    virtual_network_subnet_ids = var.subnet_ids
  }
}
