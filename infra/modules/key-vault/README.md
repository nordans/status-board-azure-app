# key-vault

Creates a dedicated Key Vault with Entra RBAC, an explicit network allowlist, purge protection and prevent_destroy. It does not create or read secret values.

Inputs: `name`, `tenant_id`, `operator_ipv4_addresses`, `subnet_ids`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `id`, `name`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
