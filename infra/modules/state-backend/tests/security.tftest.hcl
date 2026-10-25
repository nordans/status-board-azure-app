mock_provider "azurerm" {}

variables {
  resource_group_name     = "rg-statusboard-dev"
  location                = "westeurope"
  name                    = "ststatusboardtf00000001"
  operator_ipv4_addresses = ["203.0.113.10"]
}

run "state_access_and_recovery" {
  command = plan

  assert {
    condition = (
      !azurerm_storage_account.state.shared_access_key_enabled &&
      !azurerm_storage_account.state.allow_nested_items_to_be_public &&
      azurerm_storage_container.state.container_access_type == "private" &&
      azurerm_storage_container.bootstrap.container_access_type == "private" &&
      azurerm_storage_container.plans.container_access_type == "private"
    )
    error_message = "State must require Entra authentication and disallow public blob access."
  }

  assert {
    condition = (
      azurerm_storage_container.bootstrap.name != azurerm_storage_container.state.name &&
      azurerm_storage_container.plans.name != azurerm_storage_container.state.name &&
      azurerm_storage_container.bootstrap.name != azurerm_storage_container.plans.name
    )
    error_message = "Bootstrap state, platform state and saved plans must use separate private containers."
  }

  assert {
    condition = (
      azurerm_storage_account.state.network_rules[0].default_action == "Deny" &&
      azurerm_storage_account.state.network_rules[0].ip_rules == var.operator_ipv4_addresses &&
      contains(azurerm_storage_account.state.network_rules[0].bypass, "None")
    )
    error_message = "State network access must be limited to the operator allowlist without a service bypass."
  }

  assert {
    condition = (
      azurerm_storage_account.state.blob_properties[0].versioning_enabled &&
      azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days >= 30 &&
      azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days >= 30
    )
    error_message = "State must retain previous versions and deleted blobs and containers."
  }
}

run "reject_empty_state_allowlist" {
  command = plan

  variables {
    operator_ipv4_addresses = []
  }

  expect_failures = [var.operator_ipv4_addresses]
}
