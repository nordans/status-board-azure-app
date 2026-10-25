variable "name" {
  description = "Managed identity name."
  type        = string
}

variable "federated_credential_name" {
  description = "Federated credential name."
  type        = string
}

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer trusted by this identity."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace allowed to use the identity."
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account allowed to use the identity."
  type        = string
}

variable "key_vault_id" {
  description = "Dedicated vault resource ID on which the identity receives Key Vault Secrets User."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group for the resources."
  type        = string
}

variable "location" {
  description = "Azure region for the resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}
