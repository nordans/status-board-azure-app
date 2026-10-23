# state-backend

Creates an Entra-only state Storage Account and a private Blob container with firewall restrictions, versioning, soft delete and prevent_destroy. The calling root owns the resource group and state migration.

Inputs: `name`, `container_name`, `operator_ipv4_addresses`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `storage_account_name`, `container_name`, `container_id`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
