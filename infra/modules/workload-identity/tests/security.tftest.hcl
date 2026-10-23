mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-dev-app"
      client_id    = "00000000-0000-0000-0000-000000000014"
      principal_id = "00000000-0000-0000-0000-000000000015"
      tenant_id    = "00000000-0000-0000-0000-000000000002"
    }
  }
}

variables {
  resource_group_name       = "rg-statusboard-dev"
  location                  = "westeurope"
  name                      = "id-statusboard-dev-app"
  federated_credential_name = "status-board-service-account"
  oidc_issuer_url           = "https://example.oic.prod-aks.azure.com/tenant/cluster/"
  namespace                 = "status-board"
  service_account_name      = "status-board"
  key_vault_id              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.KeyVault/vaults/kv-statusboard-00000001"
}

run "federated_secret_access" {
  command = plan

  assert {
    condition = (
      azurerm_federated_identity_credential.app.subject == "system:serviceaccount:status-board:status-board" &&
      azurerm_federated_identity_credential.app.issuer == var.oidc_issuer_url &&
      azurerm_federated_identity_credential.app.audience == tolist(["api://AzureADTokenExchange"])
    )
    error_message = "Federation must trust only the supplied AKS issuer and Kubernetes service account."
  }

  assert {
    condition = (
      azurerm_role_assignment.app_secrets.role_definition_name == "Key Vault Secrets User" &&
      azurerm_role_assignment.app_secrets.scope == var.key_vault_id &&
      azurerm_role_assignment.app_secrets.principal_id == azurerm_user_assigned_identity.app.principal_id
    )
    error_message = "The workload must have read-only access on the supplied vault through its own identity."
  }
}
