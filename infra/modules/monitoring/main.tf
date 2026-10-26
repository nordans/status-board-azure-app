locals {
  application_rules = jsondecode(file("${path.module}/../../../observability/rules.json")).groups[0].rules
  log_streams       = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
}

resource "azapi_resource" "logs" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "law-${var.name_prefix}"
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  body = {
    properties = {
      sku             = { name = "PerGB2018" }
      retentionInDays = 30
      workspaceCapping = {
        dailyQuotaGb = 1
      }
      features = {
        disableLocalAuth                            = true
        enableLogAccessUsingOnlyResourcePermissions = false
      }
      publicNetworkAccessForIngestion = "Enabled"
      publicNetworkAccessForQuery     = "Enabled"
    }
  }
}

resource "azurerm_monitor_workspace" "metrics" {
  name                          = "amw-${var.name_prefix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_monitor_data_collection_endpoint" "metrics" {
  name                          = "dce-${var.name_prefix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  kind                          = "Linux"
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_monitor_data_collection_rule" "metrics" {
  name                        = "dcr-${var.name_prefix}-metrics"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  kind                        = "Linux"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.metrics.id
  tags                        = var.tags
  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.metrics.id
      name               = "metrics"
    }
  }
  data_sources {
    prometheus_forwarder {
      name    = "prometheus"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }
  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["metrics"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "metrics" {
  name                    = "status-board-metrics"
  target_resource_id      = var.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.metrics.id
}

resource "azurerm_monitor_data_collection_rule" "logs" {
  name                = "dcr-${var.name_prefix}-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  tags                = var.tags
  destinations {
    log_analytics {
      workspace_resource_id = azapi_resource.logs.id
      name                  = "logs"
    }
  }
  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.log_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Include"
          namespaces             = ["status-board", "status-board-ingress", "cert-manager"]
          enableContainerLogV2   = true
        }
      })
    }
  }
  data_flow {
    streams      = ["Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
    destinations = ["logs"]
  }
  data_flow {
    streams       = ["Microsoft-ContainerLogV2"]
    destinations  = ["logs"]
    transform_kql = "source | where PodNamespace in ('status-board', 'status-board-ingress', 'cert-manager')"
  }
}

resource "azurerm_monitor_data_collection_rule_association" "logs" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = var.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.logs.id
}

resource "azurerm_monitor_diagnostic_setting" "control_plane" {
  name                           = "status-board-control-plane"
  target_resource_id             = var.cluster_id
  log_analytics_workspace_id     = azapi_resource.logs.id
  log_analytics_destination_type = "Dedicated"
  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-controller-manager"
  }
  enabled_log {
    category = "kube-scheduler"
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "application" {
  name                = "status-board-application"
  resource_group_name = var.resource_group_name
  location            = var.location
  cluster_name        = var.cluster_name
  interval            = "PT1M"
  scopes              = [azurerm_monitor_workspace.metrics.id, var.cluster_id]
  tags                = var.tags
  dynamic "rule" {
    for_each = local.application_rules
    content {
      alert       = rule.value.alert
      expression  = rule.value.expr
      for         = "PT${trimsuffix(rule.value.for, "m")}M"
      severity    = rule.value.labels.severity == "critical" ? 2 : 3
      labels      = rule.value.labels
      annotations = rule.value.annotations
      enabled     = true
      alert_resolution {
        auto_resolved   = true
        time_to_resolve = "PT5M"
      }
    }
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "platform" {
  name                = "status-board-platform"
  resource_group_name = var.resource_group_name
  location            = var.location
  cluster_name        = var.cluster_name
  interval            = "PT1M"
  scopes              = [azurerm_monitor_workspace.metrics.id, var.cluster_id]
  tags                = var.tags
  rule {
    alert      = "KubernetesNodeNotReady"
    expression = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} == 0"
    for        = "PT5M"
    severity   = 2
    annotations = {
      summary = "A Kubernetes node has not been Ready for five minutes."
    }
    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT5M"
    }
  }
  rule {
    alert      = "StatusBoardDeploymentUnavailable"
    expression = "kube_deployment_status_replicas_available{namespace=\"status-board\",deployment=\"status-board\"} < 1"
    for        = "PT2M"
    severity   = 2
    annotations = {
      summary = "The Status Board deployment has no available replica."
    }
    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT5M"
    }
  }
}
