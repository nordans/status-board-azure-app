terraform {
  required_version = "~> 1.17.0"

  backend "azurerm" {
    use_azuread_auth = true
  }

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.11.0"
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"

  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
