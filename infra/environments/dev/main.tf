data "azurerm_client_config" "current" {}

locals {
  name            = "${var.name_prefix}-dev"
  suffix          = substr(sha256("${var.subscription_id}:${local.name}"), 0, 8)
  namespace       = "status-board"
  service_account = "status-board"
  tags = {
    application = "status-board"
    environment = "dev"
    managed_by  = "terraform"
  }
}

data "azurerm_resource_group" "platform" {
  name = "rg-${local.name}"
}

module "network" {
  source               = "../../modules/network"
  name                 = "vnet-${local.name}"
  resource_group_name  = data.azurerm_resource_group.platform.name
  location             = var.location
  address_space        = ["10.42.0.0/16"]
  node_subnet_prefixes = ["10.42.0.0/24"]
  tags                 = local.tags
}

module "registry" {
  source              = "../../modules/container-registry"
  name                = "${var.name_prefix}dev${local.suffix}"
  resource_group_name = data.azurerm_resource_group.platform.name
  location            = var.location
  sku                 = "Basic"
  tags                = local.tags
}

module "key_vault" {
  source                  = "../../modules/key-vault"
  name                    = "kv-${var.name_prefix}-${local.suffix}"
  resource_group_name     = data.azurerm_resource_group.platform.name
  location                = var.location
  tenant_id               = data.azurerm_client_config.current.tenant_id
  operator_ipv4_addresses = var.operator_ipv4_addresses
  subnet_ids              = [module.network.node_subnet_id]
  tags                    = local.tags
}

module "aks" {
  source                 = "../../modules/aks"
  name                   = "aks-${local.name}"
  name_prefix            = local.name
  resource_group_name    = data.azurerm_resource_group.platform.name
  location               = var.location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  subnet_id              = module.network.node_subnet_id
  registry_id            = module.registry.id
  kubernetes_version     = var.kubernetes_version
  node_vm_size           = var.node_vm_size
  node_count             = 2
  api_authorized_cidrs   = var.aks_api_authorized_cidrs
  admin_group_object_ids = var.aks_admin_group_object_ids
  pod_cidr               = "10.244.0.0/16"
  service_cidr           = "10.43.0.0/16"
  dns_service_ip         = "10.43.0.10"
  tags                   = local.tags
}

module "workload_identity" {
  source                    = "../../modules/workload-identity"
  name                      = "id-${local.name}-app"
  resource_group_name       = data.azurerm_resource_group.platform.name
  location                  = var.location
  federated_credential_name = "status-board-service-account"
  oidc_issuer_url           = module.aks.oidc_issuer_url
  namespace                 = local.namespace
  service_account_name      = local.service_account
  key_vault_id              = module.key_vault.id
  tags                      = local.tags
}
