variable "subscription_id" {
  description = "Azure subscription containing the Terraform state backend."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "Provide an Azure subscription UUID."
  }
}

variable "name_prefix" {
  description = "Project prefix used in resource names."
  type        = string
  default     = "statusboard"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.name_prefix))
    error_message = "Use 3 to 12 lowercase letters or digits, starting with a letter."
  }
}

variable "location" {
  description = "Azure region for the state backend."
  type        = string
  default     = "westeurope"
}

variable "operator_ipv4_addresses" {
  description = "Public IPv4 addresses allowed to access the state storage data plane."
  type        = set(string)

  validation {
    condition = length(var.operator_ipv4_addresses) > 0 && alltrue([
      for address in var.operator_ipv4_addresses : can(cidrnetmask("${address}/32"))
    ])
    error_message = "Provide at least one IPv4 address without a CIDR suffix."
  }
}
