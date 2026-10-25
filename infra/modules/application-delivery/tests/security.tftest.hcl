mock_provider "azurerm" {
  override_during = plan
}

variables {
  name_prefix                = "statusboard"
  resource_group_name        = "rg-statusboard-tfstate"
  location                   = "northeurope"
  github_oidc_subject_prefix = "repo:owner@123/repository@456"
  workload_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev"
  cluster_id                 = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerService/managedClusters/aks-statusboard-dev"
  registry_id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerRegistry/registries/statusboarddev1234"
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
