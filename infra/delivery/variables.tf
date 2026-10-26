variable "subscription_id" {
  description = "Subscription containing the existing platform."
  type        = string
}

variable "name_prefix" {
  description = "Project prefix matching the existing bootstrap and platform."
  type        = string
  default     = "statusboard"
}

variable "location" {
  description = "Azure region for the delivery identities."
  type        = string
}

variable "aks_name" {
  description = "Existing AKS name from the development root output."
  type        = string
}

variable "acr_name" {
  description = "Existing ACR name, without the .azurecr.io suffix."
  type        = string
}

variable "github_oidc_subject_prefix" {
  description = "Exact immutable repository subject prefix returned by GitHub."
  type        = string
}

variable "monitoring_enabled" {
  description = "Grant linked workspace authorization when the platform monitoring module is enabled."
  type        = bool
  default     = true
}
