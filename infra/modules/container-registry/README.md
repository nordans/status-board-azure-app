# container-registry

Creates an Azure Container Registry with administrator credentials disabled. Image pull and push role assignments are managed by consumers.

Inputs: `name`, `sku`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `id`, `login_server`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
