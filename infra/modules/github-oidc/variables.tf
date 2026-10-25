variable "name_prefix" {
  description = "Prefix for deployment identities and custom roles."
  type        = string
}

variable "resource_group_name" {
  description = "Existing management resource group for deployment identities."
  type        = string
}

variable "location" {
  description = "Azure region for deployment identities."
  type        = string
}

variable "tags" {
  description = "Tags applied to managed identities."
  type        = map(string)
  default     = {}
}

variable "github_oidc_subject_prefix" {
  description = "Exact sub_claim_prefix returned by the GitHub OIDC customization API."
  type        = string

  validation {
    condition     = can(regex("^repo:[^:]+/[^:]+$", var.github_oidc_subject_prefix))
    error_message = "Provide a repository OIDC subject prefix without an environment or branch suffix."
  }
}

variable "workload_resource_group_id" {
  description = "Scope limiting platform permissions to the development resource group."
  type        = string
}

variable "state_resource_group_id" {
  description = "Management resource group in which the backend network role is defined."
  type        = string
}

variable "storage_account_id" {
  description = "Single state account on which temporary network access can be managed."
  type        = string
}

variable "state_container_id" {
  description = "Development state container scope, excluding bootstrap state."
  type        = string
}

variable "plan_container_id" {
  description = "Private saved-plan container scope."
  type        = string
}
