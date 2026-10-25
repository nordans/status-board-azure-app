# state-backend

Creates an Entra-only state Storage Account with separate private containers for development state, bootstrap state and saved plans. Firewall restrictions, versioning, soft delete and prevent_destroy are enabled. The calling root owns the resource group, role assignments and state migration.

Inputs: `name`, `container_name`, `operator_ipv4_addresses`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `storage_account_name`, `storage_account_id`, `container_name`, `container_id`, `bootstrap_container_name`, `plan_container_name`, `plan_container_id`. Pipeline data roles must exclude the bootstrap container.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
