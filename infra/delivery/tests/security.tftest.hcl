mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev"
    }
  }
}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000001"
  location                   = "northeurope"
  aks_name                   = "aks-statusboard-dev"
  acr_name                   = "statusboarddev1234"
  github_oidc_subject_prefix = "repo:owner@123/repository@456"
}

run "delivery_contract" {
  command = plan
  assert {
    condition     = toset(keys(output.github_secrets)) == toset(["AZURE_APP_PUBLISH_CLIENT_ID", "AZURE_APP_DEPLOY_CLIENT_ID", "AZURE_APP_NETWORK_CLIENT_ID"])
    error_message = "Application delivery must export three separate identity client IDs."
  }
}
