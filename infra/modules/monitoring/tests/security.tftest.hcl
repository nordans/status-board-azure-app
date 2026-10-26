mock_provider "azapi" {
  override_during = plan
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.OperationalInsights/workspaces/law-statusboard-dev"
    }
  }
}
mock_provider "azurerm" {
  override_during = plan
  mock_resource "azurerm_monitor_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.Monitor/accounts/amw-statusboard-dev"
    }
  }
  mock_resource "azurerm_monitor_data_collection_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.Insights/dataCollectionEndpoints/dce-statusboard-dev"
    }
  }
  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.Insights/dataCollectionRules/dcr-statusboard-dev"
    }
  }
}
variables {
  name_prefix         = "statusboard-dev"
  resource_group_name = "rg-statusboard-dev"
  resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev"
  location            = "northeurope"
  cluster_id          = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-statusboard-dev/providers/Microsoft.ContainerService/managedClusters/aks-statusboard-dev"
  cluster_name        = "aks-statusboard-dev"
}
run "collection_and_access_boundaries" {
  command = plan
  assert {
    condition = (
      azurerm_log_analytics_solution.containers.solution_name == "ContainerInsights" &&
      azurerm_log_analytics_solution.containers.workspace_resource_id == azapi_resource.logs.id &&
      azurerm_log_analytics_solution.containers.plan[0].publisher == "Microsoft" &&
      azurerm_log_analytics_solution.containers.plan[0].product == "OMSGallery/ContainerInsights"
    )
    error_message = "Container Insights solution metadata must belong to this workspace and remain in platform state."
  }
  assert {
    condition = (
      azapi_resource.logs.body.properties.features.disableLocalAuth &&
      !azapi_resource.logs.body.properties.features.enableLogAccessUsingOnlyResourcePermissions &&
      azapi_resource.logs.body.properties.retentionInDays == 30 &&
      azapi_resource.logs.body.properties.workspaceCapping.dailyQuotaGb == 1
    )
    error_message = "Logs must require Entra workspace permissions and retain the demo volume controls."
  }
  assert {
    condition = (
      azurerm_monitor_data_collection_rule_association.logs.target_resource_id == var.cluster_id &&
      azurerm_monitor_data_collection_rule_association.metrics.target_resource_id == var.cluster_id &&
      jsondecode(azurerm_monitor_data_collection_rule.logs.data_sources[0].extension[0].extension_json).dataCollectionSettings.namespaceFilteringMode == "Include" &&
      !contains(local.log_streams, "Microsoft-ContainerInsights-Group-Default")
    )
    error_message = "Collectors must target this cluster and use explicitly selected log streams/namespaces."
  }
  assert {
    condition = anytrue([
      for flow in azurerm_monitor_data_collection_rule.logs.data_flow :
      flow.transform_kql == "source | where PodNamespace in ('status-board', 'status-board-ingress', 'cert-manager')"
    ])
    error_message = "ContainerLogV2 requires its own ingestion filter; inventory namespace settings do not filter container logs."
  }
  assert {
    condition = (
      length(azurerm_monitor_alert_prometheus_rule_group.application.rule) == 4 &&
      alltrue([for rule in azurerm_monitor_alert_prometheus_rule_group.application.rule : rule.alert_resolution[0].auto_resolved])
    )
    error_message = "All four application alerts must resolve after recovery."
  }
}
