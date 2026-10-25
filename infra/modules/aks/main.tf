resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-${var.name_prefix}-aks"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azapi_update_resource" "gateway_api" {
  type        = "Microsoft.ContainerService/managedClusters@2026-03-01"
  resource_id = azurerm_kubernetes_cluster.platform.id
  body = {
    properties = {
      ingressProfile = {
        gatewayAPI = {
          installation = "Standard"
        }
        webAppRouting = {
          gatewayAPIImplementations = {
            appRoutingIstio = {
              mode = "Enabled"
            }
          }
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "cluster_network" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${var.name_prefix}-kubelet"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_kubelet" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "image_pull" {
  scope                = var.registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "platform" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  dns_prefix                        = var.name_prefix
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Free"
  automatic_upgrade_channel         = "patch"
  node_os_upgrade_channel           = "NodeImage"
  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  tags                              = var.tags

  node_provisioning_profile {
    mode               = "Manual"
    default_node_pools = "None"
  }

  default_node_pool {
    name                        = "system"
    temporary_name_for_rotation = "systemtmp"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    vnet_subnet_id              = var.subnet_id
    max_pods                    = 30
    os_sku                      = "Ubuntu"
    os_disk_type                = "Managed"
    os_disk_size_gb             = 64
    tags                        = var.tags

    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_authorized_cidrs
  }

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  depends_on = [
    azurerm_role_assignment.cluster_network,
    azurerm_role_assignment.cluster_kubelet,
    azurerm_role_assignment.image_pull,
  ]
}
