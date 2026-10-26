locals {
  subscription_scope = "/subscriptions/${split("/", var.workload_resource_group_id)[2]}"
  environments = {
    plan  = "dev-infra-plan"
    apply = "dev-infra-apply"
  }
  plan_roles = toset(["Reader", "Azure Kubernetes Service Cluster User Role"])
  delegated_roles = toset([
    "Network Contributor",
    "Managed Identity Operator",
    "AcrPull",
    "Key Vault Secrets User",
  ])
  delegated_ids = join(", ", [for name in sort(tolist(local.delegated_roles)) : data.azurerm_role_definition.delegated[name].role_definition_id])
  blob_scopes = {
    state = var.state_container_id
    plans = var.plan_container_id
  }
  blob_assignments = {
    for pair in setproduct(keys(local.environments), keys(local.blob_scopes)) :
    "${pair[0]}-${pair[1]}" => { identity = pair[0], scope = local.blob_scopes[pair[1]] }
  }
}

data "azurerm_role_definition" "delegated" {
  for_each = local.delegated_roles
  name     = each.value
  scope    = var.workload_resource_group_id
}

resource "azurerm_user_assigned_identity" "github" {
  for_each = local.environments

  name                = "id-${var.name_prefix}-infra-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.environments

  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github[each.key].id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "${var.github_oidc_subject_prefix}:environment:${each.value}"
}

resource "azurerm_role_assignment" "plan" {
  for_each = local.plan_roles

  scope                = var.workload_resource_group_id
  role_definition_name = each.value
  principal_id         = azurerm_user_assigned_identity.github["plan"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "deploy" {
  name              = "${var.name_prefix}-platform-deploy"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Manage development platform resources and monitoring links without role administration."

  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/write",
      "Microsoft.ContainerService/managedClusters/delete",
      "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",
      "Microsoft.ContainerService/managedClusters/agentPools/read",
      "Microsoft.ContainerService/managedClusters/agentPools/write",
      "Microsoft.ContainerService/managedClusters/agentPools/delete",
      "Microsoft.ContainerRegistry/registries/read",
      "Microsoft.ContainerRegistry/registries/operationStatuses/read",
      "Microsoft.ContainerRegistry/registries/write",
      "Microsoft.ContainerRegistry/registries/delete",
      "Microsoft.KeyVault/vaults/read",
      "Microsoft.KeyVault/vaults/write",
      "Microsoft.KeyVault/vaults/delete",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/write",
      "Microsoft.Network/virtualNetworks/delete",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/virtualNetworks/subnets/write",
      "Microsoft.Network/virtualNetworks/subnets/delete",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/delete",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete",
      "Microsoft.Monitor/accounts/read",
      "Microsoft.Monitor/accounts/write",
      "Microsoft.Monitor/accounts/delete",
      "Microsoft.OperationalInsights/workspaces/read",
      "Microsoft.OperationalInsights/workspaces/write",
      "Microsoft.OperationalInsights/workspaces/delete",
      "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
      "Microsoft.OperationsManagement/solutions/read",
      "Microsoft.OperationsManagement/solutions/write",
      "Microsoft.OperationsManagement/solutions/delete",
      "Microsoft.Insights/dataCollectionEndpoints/read",
      "Microsoft.Insights/dataCollectionEndpoints/write",
      "Microsoft.Insights/dataCollectionEndpoints/delete",
      "Microsoft.Insights/dataCollectionRules/read",
      "Microsoft.Insights/dataCollectionRules/write",
      "Microsoft.Insights/dataCollectionRules/delete",
      "Microsoft.Insights/dataCollectionRuleAssociations/read",
      "Microsoft.Insights/dataCollectionRuleAssociations/write",
      "Microsoft.Insights/dataCollectionRuleAssociations/delete",
      "Microsoft.Insights/diagnosticSettings/read",
      "Microsoft.Insights/diagnosticSettings/write",
      "Microsoft.Insights/diagnosticSettings/delete",
      "Microsoft.AlertsManagement/prometheusRuleGroups/read",
      "Microsoft.AlertsManagement/prometheusRuleGroups/write",
      "Microsoft.AlertsManagement/prometheusRuleGroups/delete",
    ]
  }
}

resource "azurerm_role_assignment" "deploy" {
  scope              = var.workload_resource_group_id
  role_definition_id = azurerm_role_definition.deploy.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["apply"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "monitor_operations" {
  name              = "${var.name_prefix}-monitor-operation-reader"
  scope             = local.subscription_scope
  assignable_scopes = [local.subscription_scope]
  description       = "Read Azure Monitor asynchronous operation results for platform deployment."

  permissions {
    actions = ["Microsoft.Monitor/locations/operationResults/read"]
  }
}

resource "azurerm_role_assignment" "monitor_operations" {
  scope              = local.subscription_scope
  role_definition_id = azurerm_role_definition.monitor_operations.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["apply"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "delegate" {
  name              = "${var.name_prefix}-platform-role-delegate"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Role assignment management restricted by the four-role service-principal condition."

  permissions {
    actions = [
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
      "Microsoft.Authorization/roleDefinitions/read",
    ]
  }
}

resource "azurerm_role_assignment" "delegate" {
  scope              = var.workload_resource_group_id
  role_definition_id = azurerm_role_definition.delegate.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["apply"].principal_id
  principal_type     = "ServicePrincipal"
  condition_version  = "2.0"
  condition          = <<-CONDITION
    (
      (!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegated_ids}}
        AND
        @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
      )
    )
    AND
    (
      (!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegated_ids}}
        AND
        @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
      )
    )
  CONDITION
}

resource "azurerm_role_definition" "backend_network" {
  name              = "${var.name_prefix}-backend-network"
  scope             = var.state_resource_group_id
  assignable_scopes = [var.state_resource_group_id]
  description       = "Manage network configuration on the state account without storage keys or deletion."

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/write",
    ]
  }
}

resource "azurerm_role_assignment" "backend_network" {
  for_each = local.environments

  scope              = var.storage_account_id
  role_definition_id = azurerm_role_definition.backend_network.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github[each.key].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "blob" {
  for_each = local.blob_assignments

  scope                = each.value.scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
}
