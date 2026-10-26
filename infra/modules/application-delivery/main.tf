locals {
  environments = {
    publish = "dev-app-publish"
    deploy  = "dev-app-deploy"
    network = "dev-app-deploy"
  }
}

resource "azurerm_user_assigned_identity" "github" {
  for_each            = local.environments
  name                = "id-${var.name_prefix}-app-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each                  = local.environments
  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github[each.key].id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "${var.github_oidc_subject_prefix}:environment:${each.value}"
}

resource "azurerm_role_assignment" "publish" {
  scope                = var.registry_id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github["publish"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "registry_metadata" {
  scope                = var.registry_id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github["publish"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "credentials" {
  scope                = var.cluster_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_user_assigned_identity.github["deploy"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "application" {
  name              = "${var.name_prefix}-application-deploy"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Update application workloads and run in-pod smoke tests without namespace, Secret or RBAC administration."

  permissions {
    data_actions = [
      "Microsoft.ContainerService/managedClusters/apps/deployments/read",
      "Microsoft.ContainerService/managedClusters/apps/deployments/write",
      "Microsoft.ContainerService/managedClusters/apps/replicasets/read",
      "Microsoft.ContainerService/managedClusters/configmaps/read",
      "Microsoft.ContainerService/managedClusters/configmaps/write",
      "Microsoft.ContainerService/managedClusters/services/read",
      "Microsoft.ContainerService/managedClusters/services/write",
      "Microsoft.ContainerService/managedClusters/pods/read",
      "Microsoft.ContainerService/managedClusters/pods/exec/action",
      "Microsoft.ContainerService/managedClusters/events/read",
    ]
  }
}

resource "azurerm_role_assignment" "application" {
  scope              = "${var.cluster_id}/namespaces/${var.namespace}"
  role_definition_id = azurerm_role_definition.application.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["deploy"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "network" {
  name              = "${var.name_prefix}-application-api-network"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Read and update one AKS resource to manage temporary runner API access."

  permissions {
    actions = [
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/write",
    ]
  }
}

resource "azurerm_role_assignment" "network" {
  scope              = var.cluster_id
  role_definition_id = azurerm_role_definition.network.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["network"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "subnet_join" {
  name              = "${var.name_prefix}-application-subnet-join"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Permit linked-resource authorization on the existing AKS node subnet during cluster updates."

  permissions {
    actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
  }
}

resource "azurerm_role_assignment" "subnet_join" {
  scope              = var.node_subnet_id
  role_definition_id = azurerm_role_definition.subnet_join.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["network"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "identity_assign" {
  name              = "${var.name_prefix}-application-identity-assign"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Permit linked assignment authorization on the existing AKS control plane identity during cluster updates."

  permissions {
    actions = ["Microsoft.ManagedIdentity/userAssignedIdentities/assign/action"]
  }
}

resource "azurerm_role_assignment" "identity_assign" {
  scope              = var.control_plane_identity_id
  role_definition_id = azurerm_role_definition.identity_assign.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["network"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "monitoring_link" {
  count             = var.log_analytics_workspace_id == null ? 0 : 1
  name              = "${var.name_prefix}-application-monitoring-link"
  scope             = var.workload_resource_group_id
  assignable_scopes = [var.workload_resource_group_id]
  description       = "Permit Log Analytics linked-resource authorization when updating the monitored AKS cluster."

  permissions {
    actions = [
      "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
      "Microsoft.OperationsManagement/solutions/write",
    ]
  }
}

resource "azurerm_role_assignment" "monitoring_link" {
  count              = var.log_analytics_workspace_id == null ? 0 : 1
  scope              = var.log_analytics_workspace_id
  role_definition_id = azurerm_role_definition.monitoring_link[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.github["network"].principal_id
  principal_type     = "ServicePrincipal"
}
