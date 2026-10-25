data "azurerm_resource_group" "management" {
  name = "rg-${var.name_prefix}-tfstate"
}

data "azurerm_resource_group" "platform" {
  name = "rg-${var.name_prefix}-dev"
}

module "application_delivery" {
  source                     = "../modules/application-delivery"
  name_prefix                = var.name_prefix
  resource_group_name        = data.azurerm_resource_group.management.name
  location                   = var.location
  workload_resource_group_id = data.azurerm_resource_group.platform.id
  cluster_id                 = "${data.azurerm_resource_group.platform.id}/providers/Microsoft.ContainerService/managedClusters/${var.aks_name}"
  registry_id                = "${data.azurerm_resource_group.platform.id}/providers/Microsoft.ContainerRegistry/registries/${var.acr_name}"
  github_oidc_subject_prefix = var.github_oidc_subject_prefix
  tags = {
    application = "status-board"
    environment = "management"
    managed_by  = "terraform"
  }
}
