mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      oidc_issuer_url = "https://example.oic.prod-aks.azure.com/tenant/cluster/"
    }
  }

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000001"
  kubernetes_version         = "1.35"
  operator_ipv4_addresses    = ["203.0.113.10"]
  aks_api_authorized_cidrs   = ["203.0.113.10/32"]
  aks_admin_group_object_ids = ["00000000-0000-0000-0000-000000000003"]
}

run "identity_and_network_boundaries" {
  command = plan

  assert {
    condition = (
      azurerm_kubernetes_cluster.platform.local_account_disabled &&
      azurerm_kubernetes_cluster.platform.role_based_access_control_enabled &&
      azurerm_kubernetes_cluster.platform.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    )
    error_message = "Cluster access must use Entra and RBAC, with local administrator credentials disabled."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.platform.api_server_access_profile[0].authorized_ip_ranges == var.aks_api_authorized_cidrs &&
      azurerm_kubernetes_cluster.platform.network_profile[0].network_policy == "cilium"
    )
    error_message = "The Kubernetes API must retain its IP allowlist and support network policy enforcement."
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.platform.oidc_issuer_enabled &&
      azurerm_kubernetes_cluster.platform.workload_identity_enabled &&
      azurerm_federated_identity_credential.app.subject == "system:serviceaccount:status-board:status-board" &&
      azurerm_role_assignment.app_secrets.role_definition_name == "Key Vault Secrets User"
    )
    error_message = "The app must use a dedicated federated service account with read-only secret permissions."
  }

  assert {
    condition = (
      !azurerm_container_registry.app.admin_enabled &&
      azurerm_role_assignment.image_pull.role_definition_name == "AcrPull"
    )
    error_message = "Image pulls must use the kubelet identity without registry administrator credentials."
  }

  assert {
    condition = (
      azurerm_key_vault.app.rbac_authorization_enabled &&
      azurerm_key_vault.app.purge_protection_enabled &&
      azurerm_key_vault.app.network_acls[0].default_action == "Deny" &&
      azurerm_key_vault.app.network_acls[0].bypass == "None"
    )
    error_message = "Key Vault must require RBAC, enforce its firewall and retain deleted secrets."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.platform.key_vault_secrets_provider[0].secret_rotation_enabled
    error_message = "Mounted secrets must support automatic refresh."
  }
}

run "reject_public_api_access" {
  command = plan

  variables {
    aks_api_authorized_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.aks_api_authorized_cidrs]
}

run "reject_empty_api_allowlist" {
  command = plan

  variables {
    aks_api_authorized_cidrs = []
  }

  expect_failures = [var.aks_api_authorized_cidrs]
}

run "reject_missing_administrator_group" {
  command = plan

  variables {
    aks_admin_group_object_ids = []
  }

  expect_failures = [var.aks_admin_group_object_ids]
}
