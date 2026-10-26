data "azurerm_resource_group" "management" {
  name = "rg-${var.name_prefix}-tfstate"
}

data "azurerm_resource_group" "platform" {
  name = "rg-${var.name_prefix}-dev"
}

data "azurerm_subnet" "nodes" {
  name                 = "aks-nodes"
  virtual_network_name = "vnet-${var.name_prefix}-dev"
  resource_group_name  = data.azurerm_resource_group.platform.name
}

data "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name_prefix}-dev-aks"
  resource_group_name = data.azurerm_resource_group.platform.name
}

module "application_delivery" {
  source                     = "../modules/application-delivery"
  name_prefix                = var.name_prefix
  resource_group_name        = data.azurerm_resource_group.management.name
  location                   = var.location
  workload_resource_group_id = data.azurerm_resource_group.platform.id
  cluster_id                 = "${data.azurerm_resource_group.platform.id}/providers/Microsoft.ContainerService/managedClusters/${var.aks_name}"
  registry_id                = "${data.azurerm_resource_group.platform.id}/providers/Microsoft.ContainerRegistry/registries/${var.acr_name}"
  node_subnet_id             = data.azurerm_subnet.nodes.id
  control_plane_identity_id  = data.azurerm_user_assigned_identity.control_plane.id
  github_oidc_subject_prefix = var.github_oidc_subject_prefix
  log_analytics_workspace_id = var.monitoring_enabled ? "${data.azurerm_resource_group.platform.id}/providers/Microsoft.OperationalInsights/workspaces/law-${var.name_prefix}-dev" : null
  tags = {
    application = "status-board"
    environment = "management"
    managed_by  = "terraform"
  }
}
