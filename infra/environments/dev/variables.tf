variable "subscription_id" {
  description = "Azure subscription for the development environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "Provide an Azure subscription UUID."
  }
}

variable "monitoring_enabled" {
  description = "Deploy monitoring workspaces, agents, collection rules and alerts with the platform."
  type        = bool
  default     = true
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
  description = "Azure region for development resources."
  type        = string
  default     = "westeurope"
}

variable "kubernetes_version" {
  description = "Supported AKS minor version, selected with az aks get-versions in the target region."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Specify an AKS minor version such as 1.35."
  }
}

variable "node_vm_size" {
  description = "System node VM size; AKS requires at least 4 vCPUs and 4 GB of memory."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "operator_ipv4_addresses" {
  description = "Public operator IPv4 addresses allowed by the Key Vault firewall."
  type        = set(string)

  validation {
    condition = length(var.operator_ipv4_addresses) > 0 && alltrue([
      for address in var.operator_ipv4_addresses : can(cidrnetmask("${address}/32"))
    ])
    error_message = "Provide at least one IPv4 address without a CIDR suffix."
  }
}

variable "aks_api_authorized_cidrs" {
  description = "IPv4 networks allowed to reach the Kubernetes API; /0 is forbidden."
  type        = set(string)

  validation {
    condition = length(var.aks_api_authorized_cidrs) > 0 && alltrue([
      for cidr in var.aks_api_authorized_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "Provide at least one IPv4 CIDR and do not allow 0.0.0.0/0."
  }
}

variable "aks_admin_group_object_ids" {
  description = "Microsoft Entra security group object IDs with cluster administrator access."
  type        = set(string)

  validation {
    condition = length(var.aks_admin_group_object_ids) > 0 && alltrue([
      for id in var.aks_admin_group_object_ids : can(regex("^[0-9a-fA-F-]{36}$", id))
    ])
    error_message = "Provide at least one Microsoft Entra security group UUID."
  }
}
