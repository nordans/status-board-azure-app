mock_provider "azurerm" {
  override_during = plan
}

variables {
  resource_group_name     = "rg-statusboard-dev"
  location                = "westeurope"
  name                    = "kv-statusboard-00000001"
  tenant_id               = "00000000-0000-0000-0000-000000000002"
  operator_ipv4_addresses = ["203.0.113.10"]
  subnet_ids              = ["/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.Network/virtualNetworks/vnet-statusboard-dev/subnets/aks-nodes"]
}

run "secret_access_and_recovery" {
  command = plan

  assert {
    condition = (
      azurerm_key_vault.app.rbac_authorization_enabled &&
      azurerm_key_vault.app.purge_protection_enabled &&
      azurerm_key_vault.app.soft_delete_retention_days == 7 &&
      azurerm_key_vault.app.network_acls[0].default_action == "Deny" &&
      azurerm_key_vault.app.network_acls[0].bypass == "None"
    )
    error_message = "The vault must require RBAC, enforce its firewall and protect deleted secrets."
  }

  assert {
    condition = (
      azurerm_key_vault.app.network_acls[0].ip_rules == var.operator_ipv4_addresses &&
      azurerm_key_vault.app.network_acls[0].virtual_network_subnet_ids == var.subnet_ids
    )
    error_message = "The vault firewall must retain the supplied operator and subnet allowlists."
  }
}
