output "id" {
  description = "Cluster resource ID."
  value       = azurerm_kubernetes_cluster.platform.id
}

output "name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.platform.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer used for workload federation."
  value       = azurerm_kubernetes_cluster.platform.oidc_issuer_url
}
