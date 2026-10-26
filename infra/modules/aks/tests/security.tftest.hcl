mock_provider "azapi" {}

mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerService/managedClusters/aks-statusboard-dev"
    }
  }

  override_resource {
    target = azurerm_user_assigned_identity.cluster
    values = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-dev-aks"
      client_id    = "00000000-0000-0000-0000-000000000010"
      principal_id = "00000000-0000-0000-0000-000000000011"
      tenant_id    = "00000000-0000-0000-0000-000000000002"
    }
  }

  override_resource {
    target = azurerm_user_assigned_identity.kubelet
    values = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-statusboard-dev-kubelet"
      client_id    = "00000000-0000-0000-0000-000000000012"
      principal_id = "00000000-0000-0000-0000-000000000013"
      tenant_id    = "00000000-0000-0000-0000-000000000002"
    }
  }
}

variables {
  resource_group_name    = "rg-statusboard-dev"
  location               = "westeurope"
  name                   = "aks-statusboard-dev"
  name_prefix            = "statusboard-dev"
  tenant_id              = "00000000-0000-0000-0000-000000000002"
  subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.Network/virtualNetworks/vnet-statusboard-dev/subnets/aks-nodes"
  registry_id            = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerRegistry/registries/statusboarddev00000001"
  kubernetes_version     = "1.35"
  node_vm_size           = "Standard_D4s_v5"
  api_authorized_cidrs   = ["203.0.113.10/32"]
  admin_group_object_ids = ["00000000-0000-0000-0000-000000000003"]
  pod_cidr               = "10.244.0.0/16"
  service_cidr           = "10.43.0.0/16"
  dns_service_ip         = "10.43.0.10"
}

run "managed_monitoring_uses_entra" {
  command = plan
  variables {
    monitoring_enabled         = true
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.OperationalInsights/workspaces/law-statusboard-dev"
  }
  assert {
    condition = (
      length(azurerm_kubernetes_cluster.platform.monitor_metrics) == 1 &&
      azurerm_kubernetes_cluster.platform.oms_agent[0].msi_auth_for_monitoring_enabled &&
      azurerm_kubernetes_cluster.platform.oms_agent[0].log_analytics_workspace_id == var.log_analytics_workspace_id
    )
    error_message = "Managed monitoring must enable metrics and use managed identity for log ingestion."
  }
}

run "identity_and_network_boundaries" {
  command = plan

  assert {
    condition = (
      azapi_update_resource.gateway_api.body.properties.ingressProfile.gatewayAPI.installation == "Standard" &&
      azapi_update_resource.gateway_api.body.properties.ingressProfile.webAppRouting.gatewayAPIImplementations.appRoutingIstio.mode == "Enabled" &&
      length(keys(azapi_update_resource.gateway_api.body.properties)) == 1
    )
    error_message = "The AzAPI update must enable managed Gateway API without overwriting other cluster properties."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.platform.local_account_disabled &&
      azurerm_kubernetes_cluster.platform.role_based_access_control_enabled &&
      azurerm_kubernetes_cluster.platform.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    )
    error_message = "Cluster access must use Entra and RBAC with local administrator credentials disabled."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.platform.api_server_access_profile[0].authorized_ip_ranges == var.api_authorized_cidrs &&
      azurerm_kubernetes_cluster.platform.network_profile[0].network_policy == "cilium"
    )
    error_message = "The API must retain its allowlist and support network policy enforcement."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.platform.oidc_issuer_enabled &&
      azurerm_kubernetes_cluster.platform.workload_identity_enabled &&
      azurerm_kubernetes_cluster.platform.key_vault_secrets_provider[0].secret_rotation_enabled
    )
    error_message = "Workload federation and automatic CSI secret refresh must remain enabled."
  }

  assert {
    condition = (
      azurerm_role_assignment.image_pull.role_definition_name == "AcrPull" &&
      azurerm_role_assignment.image_pull.scope == var.registry_id &&
      azurerm_role_assignment.image_pull.principal_id == azurerm_user_assigned_identity.kubelet.principal_id
    )
    error_message = "Image pull permissions must be scoped to the supplied registry and kubelet identity."
  }

  assert {
    condition = (
      azurerm_role_assignment.cluster_network.scope == var.subnet_id &&
      azurerm_role_assignment.cluster_network.role_definition_name == "Network Contributor" &&
      azurerm_role_assignment.cluster_kubelet.scope == azurerm_user_assigned_identity.kubelet.id
    )
    error_message = "Cluster permissions must remain scoped to its subnet and kubelet identity."
  }
}

run "reject_public_api_access" {
  command = plan

  variables {
    api_authorized_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.api_authorized_cidrs]
}

run "reject_empty_api_allowlist" {
  command = plan

  variables {
    api_authorized_cidrs = []
  }

  expect_failures = [var.api_authorized_cidrs]
}

run "reject_missing_administrator_group" {
  command = plan

  variables {
    admin_group_object_ids = []
  }

  expect_failures = [var.admin_group_object_ids]
}

run "reject_undersized_system_pool" {
  command = plan

  variables {
    node_count = 1
  }

  expect_failures = [var.node_count]
}
