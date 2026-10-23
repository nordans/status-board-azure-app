locals {
  suffix = substr(sha256("${var.subscription_id}:${var.name_prefix}:tfstate"), 0, 8)
  tags = {
    application = "status-board"
    environment = "management"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-${var.name_prefix}-dev"
  location = var.location
  tags = merge(local.tags, {
    environment = "dev"
  })
}

resource "azurerm_storage_account" "state" {
  name                              = "st${var.name_prefix}tf${local.suffix}"
  resource_group_name               = azurerm_resource_group.state.name
  location                          = azurerm_resource_group.state.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  public_network_access             = "Enabled"
  tags                              = local.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
    ip_rules       = var.operator_ipv4_addresses
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}
