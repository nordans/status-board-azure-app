resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.name}-app"
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "app" {
  name                      = "status-board-service-account"
  user_assigned_identity_id = azurerm_user_assigned_identity.app.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.platform.oidc_issuer_url
  subject                   = "system:serviceaccount:${local.namespace}:${local.service_account}"
}

resource "azurerm_role_assignment" "app_secrets" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}
