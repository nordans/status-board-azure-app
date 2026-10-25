resource "azurerm_virtual_network" "platform" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = var.node_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.platform.name
  address_prefixes     = var.node_subnet_prefixes

  service_endpoint {
    service = "Microsoft.KeyVault"
  }
}
