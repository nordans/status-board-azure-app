variable "name" {
  description = "Globally unique Key Vault name."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant owning the vault."
  type        = string
}

variable "operator_ipv4_addresses" {
  description = "Public operator IPv4 addresses allowed through the vault firewall."
  type        = set(string)

  validation {
    condition     = length(var.operator_ipv4_addresses) > 0 && alltrue([for address in var.operator_ipv4_addresses : can(cidrnetmask("${address}/32"))])
    error_message = "Provide at least one IPv4 address without a CIDR suffix."
  }
}

variable "subnet_ids" {
  description = "Subnet resource IDs allowed through the vault firewall."
  type        = set(string)
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
