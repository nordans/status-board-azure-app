mock_provider "azurerm" {
  override_during = plan
}

variables {
  resource_group_name = "rg-statusboard-dev"
  location            = "westeurope"
  name                = "statusboarddev00000001"
}

run "reject_registry_admin_credentials" {
  command = plan

  assert {
    condition     = !azurerm_container_registry.app.admin_enabled
    error_message = "Registry administrator credentials must remain disabled."
  }
}
