mock_provider "azapi" {}

mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerService/managedClusters/aks-statusboard-dev"
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

run "development_contract" {
  command = plan

  assert {
    condition     = output.aks_name == "aks-statusboard-dev" && startswith(output.key_vault_name, "kv-statusboard-")
    error_message = "Development resource names must remain stable."
  }

  assert {
    condition     = output.kubernetes_namespace == "status-board" && output.kubernetes_service_account == "status-board"
    error_message = "The exported Kubernetes identity must match the deployment contract."
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
