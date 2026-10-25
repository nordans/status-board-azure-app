variable "name" {
  description = "Globally unique storage account name."
  type        = string
}

variable "container_name" {
  description = "Private state container name."
  type        = string
  default     = "tfstate"
}

variable "operator_ipv4_addresses" {
  description = "Public operator IPv4 addresses allowed through the storage firewall."
  type        = set(string)

  validation {
    condition     = length(var.operator_ipv4_addresses) > 0 && alltrue([for address in var.operator_ipv4_addresses : can(cidrnetmask("${address}/32"))])
    error_message = "Provide at least one IPv4 address without a CIDR suffix."
  }
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
