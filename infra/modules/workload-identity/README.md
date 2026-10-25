# workload-identity

Creates a managed identity federated to one Kubernetes service account and assigns read-only secret access on a dedicated Key Vault. It creates no Kubernetes resources or secret values.

Inputs: `name`, `federated_credential_name`, `oidc_issuer_url`, `namespace`, `service_account_name`, `key_vault_id`, `resource_group_name`, `location`, `tags`. Types, descriptions, defaults and validation are declared in `variables.tf`.

Outputs: `client_id`, `principal_id`.

The module inherits the AzureRM provider from its caller. See [infrastructure operations](../../README.md) for backend setup and validation.
