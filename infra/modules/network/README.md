# network

Creates a virtual network and an AKS node subnet with the Microsoft.KeyVault service endpoint.

Inputs: `name`, `address_space`, `node_subnet_name`, `node_subnet_prefixes`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `id`, `node_subnet_id`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
