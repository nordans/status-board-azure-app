variable "name" {
  description = "AKS cluster name."
  type        = string
}

variable "name_prefix" {
  description = "DNS prefix and prefix for cluster and kubelet identity names."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant used for cluster authentication."
  type        = string
}

variable "subnet_id" {
  description = "Subnet resource ID for cluster nodes."
  type        = string
}

variable "registry_id" {
  description = "Registry resource ID on which the kubelet receives AcrPull."
  type        = string
}

variable "kubernetes_version" {
  description = "Supported AKS minor version."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Specify an AKS minor version such as 1.35."
  }
}

variable "node_vm_size" {
  description = "System node VM size; must meet AKS system pool requirements."
  type        = string
}

variable "node_count" {
  description = "Number of system nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2 && floor(var.node_count) == var.node_count
    error_message = "Use an integer node count of at least two."
  }
}

variable "api_authorized_cidrs" {
  description = "IPv4 networks allowed to reach the Kubernetes API."
  type        = set(string)

  validation {
    condition     = length(var.api_authorized_cidrs) > 0 && alltrue([for cidr in var.api_authorized_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)])
    error_message = "Provide at least one IPv4 CIDR and do not allow 0.0.0.0/0."
  }
}

variable "admin_group_object_ids" {
  description = "Microsoft Entra security groups with cluster administrator access."
  type        = set(string)

  validation {
    condition     = length(var.admin_group_object_ids) > 0 && alltrue([for id in var.admin_group_object_ids : can(regex("^[0-9a-fA-F-]{36}$", id))])
    error_message = "Provide at least one Microsoft Entra security group UUID."
  }
}

variable "pod_cidr" {
  description = "Nonoverlapping IPv4 range for overlay pod addresses."
  type        = string
}

variable "service_cidr" {
  description = "Nonoverlapping IPv4 range for Kubernetes service addresses."
  type        = string
}

variable "dns_service_ip" {
  description = "Cluster DNS service IPv4 address within service_cidr."
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
