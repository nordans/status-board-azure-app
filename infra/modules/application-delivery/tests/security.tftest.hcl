mock_provider "azurerm" {
  override_during = plan
}

override_resource {
  target          = azurerm_user_assigned_identity.github["network"]
  override_during = plan
  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-tfstate/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-app-network"
    principal_id = "00000000-0000-0000-0000-000000000005"
  }
}

variables {
  name_prefix                = "statusboard"
  resource_group_name        = "rg-statusboard-tfstate"
  location                   = "northeurope"
  github_oidc_subject_prefix = "repo:owner@123/repository@456"
  workload_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev"
  cluster_id                 = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerService/managedClusters/aks-statusboard-dev"
  registry_id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerRegistry/registries/statusboarddev1234"
  node_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.Network/virtualNetworks/vnet-statusboard-dev/subnets/aks-nodes"
  control_plane_identity_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-dev-aks"
}

run "delivery_permissions" {
  command = plan

  assert {
    condition = (
      azurerm_federated_identity_credential.github["publish"].subject == "repo:owner@123/repository@456:environment:dev-app-publish" &&
      azurerm_federated_identity_credential.github["deploy"].subject == "repo:owner@123/repository@456:environment:dev-app-deploy" &&
      azurerm_federated_identity_credential.github["network"].subject == azurerm_federated_identity_credential.github["deploy"].subject
    )
    error_message = "Only the exact delivery environments may exchange tokens for these identities."
  }

  assert {
    condition = (
      azurerm_role_assignment.publish.scope == var.registry_id &&
      azurerm_role_assignment.publish.role_definition_name == "AcrPush" &&
      azurerm_role_assignment.registry_metadata.scope == var.registry_id &&
      azurerm_role_assignment.registry_metadata.role_definition_name == "Reader" &&
      azurerm_role_assignment.credentials.scope == var.cluster_id &&
      azurerm_role_assignment.credentials.role_definition_name == "Azure Kubernetes Service Cluster User Role" &&
      azurerm_role_assignment.application.scope == "${var.cluster_id}/namespaces/status-board"
    )
    error_message = "Publishing must target one registry; Kubernetes credentials and namespace access must target one cluster."
  }

  assert {
    condition = (
      azurerm_role_assignment.network.scope == var.cluster_id &&
      toset(azurerm_role_definition.network.permissions[0].actions) == toset([
        "Microsoft.ContainerService/managedClusters/read", "Microsoft.ContainerService/managedClusters/write"
      ])
    )
    error_message = "The network identity may update one cluster, without deletion, credentials or role administration."
  }

  assert {
    condition = (
      azurerm_role_assignment.subnet_join.scope == var.node_subnet_id &&
      azurerm_role_assignment.subnet_join.principal_id == azurerm_user_assigned_identity.github["network"].principal_id &&
      toset(azurerm_role_definition.subnet_join.permissions[0].actions) == toset([
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]) &&
      length(coalesce(azurerm_role_definition.subnet_join.permissions[0].data_actions, [])) == 0
    )
    error_message = "Linked-resource authorization must grant only subnet join to the network identity on the node subnet."
  }

  assert {
    condition = (
      azurerm_role_assignment.identity_assign.scope == var.control_plane_identity_id &&
      azurerm_role_assignment.identity_assign.principal_id == azurerm_user_assigned_identity.github["network"].principal_id &&
      toset(azurerm_role_definition.identity_assign.permissions[0].actions) == toset([
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action"
      ]) &&
      length(coalesce(azurerm_role_definition.identity_assign.permissions[0].data_actions, [])) == 0
    )
    error_message = "Linked identity authorization must grant only assignment of the existing control plane identity to the network principal."
  }

  assert {
    condition = (
      length(azurerm_role_definition.application.permissions[0].data_actions) == 10 &&
      alltrue([
        for action in azurerm_role_definition.application.permissions[0].data_actions :
        !strcontains(action, "*") && !strcontains(action, "secrets/") &&
        !strcontains(action, "rolebindings/") && !strcontains(action, "namespaces/") &&
        !strcontains(action, "serviceaccounts/") && !endswith(action, "/delete")
      ]) &&
      contains(azurerm_role_definition.application.permissions[0].data_actions, "Microsoft.ContainerService/managedClusters/pods/exec/action")
    )
    error_message = "Application delivery must not administer Secrets, service accounts, namespaces, RBAC or resource deletion."
  }
}

run "reject_branch_subject" {
  command = plan
  variables {
    github_oidc_subject_prefix = "repo:owner/repository:ref:refs/heads/main"
  }
  expect_failures = [var.github_oidc_subject_prefix]
}

run "monitoring_link_is_workspace_scoped" {
  command = plan
  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.OperationalInsights/workspaces/law-statusboard-dev"
  }
  assert {
    condition = (
      azurerm_role_assignment.monitoring_link[0].scope == var.log_analytics_workspace_id &&
      azurerm_role_assignment.monitoring_link[0].principal_id == azurerm_user_assigned_identity.github["network"].principal_id &&
      toset(azurerm_role_definition.monitoring_link[0].permissions[0].actions) == toset([
        "Microsoft.OperationalInsights/workspaces/read", "Microsoft.OperationalInsights/workspaces/sharedKeys/action", "Microsoft.OperationsManagement/solutions/read", "Microsoft.OperationsManagement/solutions/write"
      ]) &&
      length(coalesce(azurerm_role_definition.monitoring_link[0].permissions[0].data_actions, [])) == 0
    )
    error_message = "Only the network identity may receive the four linked-workspace actions on the exact workspace."
  }
}

run "reject_unrelated_monitoring_workspace" {
  command = plan
  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-unrelated/providers/Microsoft.OperationalInsights/workspaces/law-unrelated"
  }
  expect_failures = [var.log_analytics_workspace_id]
}
