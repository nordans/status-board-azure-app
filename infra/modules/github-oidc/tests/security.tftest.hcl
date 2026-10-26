mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_role_definition" {
    defaults = {
      role_definition_id = "00000000-0000-0000-0000-000000000005"
    }
  }
}

variables {
  name_prefix                = "statusboard"
  resource_group_name        = "rg-statusboard-tfstate"
  location                   = "westeurope"
  github_oidc_subject_prefix = "repo:owner@123/repository@456"
  workload_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev"
  state_resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate"
  storage_account_id         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate/providers/Microsoft.Storage/storageAccounts/ststatusboardtf00000001"
  state_container_id         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate/providers/Microsoft.Storage/storageAccounts/ststatusboardtf00000001/blobServices/default/containers/tfstate"
  plan_container_id          = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate/providers/Microsoft.Storage/storageAccounts/ststatusboardtf00000001/blobServices/default/containers/tfplans"
}

run "repository_and_environment_trust" {
  command = plan

  assert {
    condition = (
      azurerm_federated_identity_credential.github["plan"].subject == "repo:owner@123/repository@456:environment:dev-infra-plan" &&
      azurerm_federated_identity_credential.github["apply"].subject == "repo:owner@123/repository@456:environment:dev-infra-apply"
    )
    error_message = "Each identity must trust only its exact repository environment subject."
  }

  assert {
    condition = (
      local.plan_roles == toset(["Reader", "Azure Kubernetes Service Cluster User Role"]) &&
      azurerm_role_assignment.deploy.scope == var.workload_resource_group_id &&
      azurerm_role_assignment.delegate.scope == var.workload_resource_group_id
    )
    error_message = "Planning and deployment permissions must remain separate and scoped to the workload resource group."
  }

  assert {
    condition = (
      local.delegated_roles == toset(["Network Contributor", "Managed Identity Operator", "AcrPull", "Key Vault Secrets User"]) &&
      azurerm_role_assignment.delegate.condition_version == "2.0" &&
      strcontains(azurerm_role_assignment.delegate.condition, "@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId]") &&
      strcontains(azurerm_role_assignment.delegate.condition, "@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId]") &&
      strcontains(azurerm_role_assignment.delegate.condition, "{'ServicePrincipal'}")
    )
    error_message = "Delegation must constrain both role creation and deletion to the four application roles and service principals."
  }

  assert {
    condition = (
      !contains(azurerm_role_definition.deploy.permissions[0].actions, "*") &&
      !contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.Authorization/roleAssignments/write") &&
      contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.OperationalInsights/workspaces/sharedKeys/action") &&
      contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.OperationsManagement/solutions/write") &&
      contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.OperationsManagement/solutions/delete") &&
      contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.Monitor/accounts/write") &&
      contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.AlertsManagement/prometheusRuleGroups/delete") &&
      contains(azurerm_role_definition.deploy.permissions[0].actions, "Microsoft.ContainerRegistry/registries/operationStatuses/read") &&
      toset(azurerm_role_definition.backend_network.permissions[0].actions) == toset(["Microsoft.Storage/storageAccounts/read", "Microsoft.Storage/storageAccounts/write"])
    )
    error_message = "Resource deployment must not grant wildcard actions or unconditional RBAC administration."
  }

  assert {
    condition = alltrue([
      for assignment in azurerm_role_assignment.blob :
      contains([var.state_container_id, var.plan_container_id], assignment.scope)
    ])
    error_message = "Pipeline data permissions must exclude the bootstrap state container."
  }
}

run "reject_unscoped_subject" {
  command = plan

  variables {
    github_oidc_subject_prefix = "repo:owner/repository:ref:refs/heads/main"
  }

  expect_failures = [var.github_oidc_subject_prefix]
}

run "monitor_operation_results_access" {
  command = plan

  override_resource {
    target          = azurerm_user_assigned_identity.github["apply"]
    override_during = plan
    values = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-infra-apply"
      principal_id = "00000000-0000-0000-0000-000000000006"
    }
  }

  override_resource {
    target          = azurerm_user_assigned_identity.github["plan"]
    override_during = plan
    values = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-infra-plan"
      principal_id = "00000000-0000-0000-0000-000000000007"
    }
  }

  assert {
    condition = (
      azurerm_role_definition.monitor_operations.scope == "/subscriptions/00000000-0000-0000-0000-000000000001" &&
      toset(azurerm_role_definition.monitor_operations.assignable_scopes) == toset(["/subscriptions/00000000-0000-0000-0000-000000000001"]) &&
      toset(azurerm_role_definition.monitor_operations.permissions[0].actions) == toset(["Microsoft.Monitor/locations/operationResults/read"]) &&
      length(coalesce(azurerm_role_definition.monitor_operations.permissions[0].data_actions, [])) == 0 &&
      azurerm_role_assignment.monitor_operations.scope == azurerm_role_definition.monitor_operations.scope &&
      azurerm_role_assignment.monitor_operations.principal_id == azurerm_user_assigned_identity.github["apply"].principal_id &&
      azurerm_role_assignment.monitor_operations.principal_type == "ServicePrincipal"
    )
    error_message = "Only Apply may receive the single subscription-scoped Azure Monitor operation-result read action without data access."
  }
}
