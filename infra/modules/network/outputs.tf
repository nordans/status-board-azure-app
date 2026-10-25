output "id" {
  description = "Virtual network resource ID."
  value       = azurerm_virtual_network.platform.id
}

output "node_subnet_id" {
  description = "Subnet resource ID for AKS nodes and Key Vault network access."
  value       = azurerm_subnet.nodes.id
}
