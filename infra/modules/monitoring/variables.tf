variable "name_prefix" {
  description = "Prefix for monitoring resources."
  type        = string
}

variable "resource_group_name" {
  description = "Existing workload resource group name."
  type        = string
}

variable "resource_group_id" {
  description = "Existing workload resource group ID."
  type        = string
}

variable "location" {
  description = "Azure region shared with AKS."
  type        = string
}

variable "cluster_id" {
  description = "AKS resource ID for collection associations and alerts."
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name for Prometheus alert scoping."
  type        = string
}

variable "tags" {
  description = "Tags applied to monitoring resources."
  type        = map(string)
  default     = {}
}
