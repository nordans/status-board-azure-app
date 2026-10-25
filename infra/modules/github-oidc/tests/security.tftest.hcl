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
