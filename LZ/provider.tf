terraform {
  required_version = ">= 1.7.0"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }

}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    # Private endpoints do not exist during initial account creation.
    storage {
      data_plane_available = false
    }

    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
