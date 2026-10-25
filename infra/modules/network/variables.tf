variable "name" {
  description = "Virtual network name."
  type        = string
}

variable "address_space" {
  description = "IPv4 address spaces assigned to the virtual network."
  type        = list(string)
}

variable "node_subnet_name" {
  description = "Name of the AKS node subnet."
  type        = string
  default     = "aks-nodes"
}

variable "node_subnet_prefixes" {
  description = "IPv4 address prefixes assigned to the node subnet."
  type        = list(string)
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
