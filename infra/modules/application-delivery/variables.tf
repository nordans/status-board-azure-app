variable "name_prefix" {
  description = "Project prefix for delivery identities and custom roles."
  type        = string
}

variable "resource_group_name" {
  description = "Existing management resource group for delivery identities."
  type        = string
}

variable "location" {
  description = "Region for delivery identities."
  type        = string
}

variable "workload_resource_group_id" {
  description = "Resource group in which the delivery role definitions are assignable."
  type        = string
}

variable "cluster_id" {
  description = "Single AKS resource to which delivery access is granted."
  type        = string
}

variable "registry_id" {
  description = "Single RBAC-mode registry to which images may be pushed."
  type        = string
}

variable "namespace" {
  description = "Existing application namespace managed by the cluster operator."
  type        = string
  default     = "status-board"
}

variable "github_oidc_subject_prefix" {
  description = "Exact repository sub_claim_prefix returned by the GitHub API."
  type        = string

  validation {
    condition     = can(regex("^repo:[^:]+/[^:]+$", var.github_oidc_subject_prefix))
    error_message = "Provide the exact repository subject prefix without an environment suffix."
  }
}

variable "tags" {
  description = "Tags for delivery identities."
  type        = map(string)
  default     = {}
}
