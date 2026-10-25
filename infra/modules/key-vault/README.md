# key-vault

Creates a dedicated Key Vault with Entra RBAC, an explicit network allowlist, purge protection and seven-day soft-delete retention. It does not create or read secret values.

The ephemeral development platform permits vault deletion through a reviewed saved Terraform plan. Purge protection remains enabled: a deleted vault and its name remain reserved during retention. The development provider disables automatic purge on destroy. Recovering a deleted vault is an operator task; recovery does not restore its former role assignments. See [infrastructure operations](../../README.md) before redeploying a recently deleted vault.

Inputs: `name`, `tenant_id`, `operator_ipv4_addresses`, `subnet_ids`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `id`, `name`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
