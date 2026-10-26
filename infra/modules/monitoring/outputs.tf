output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for the AKS agent."
  value       = azapi_resource.logs.id
}

output "monitor_workspace_id" {
  description = "Managed Prometheus workspace ID."
  value       = azurerm_monitor_workspace.metrics.id
}

output "prometheus_query_endpoint" {
  description = "Entra-authenticated Prometheus query endpoint."
  value       = azurerm_monitor_workspace.metrics.query_endpoint
}
