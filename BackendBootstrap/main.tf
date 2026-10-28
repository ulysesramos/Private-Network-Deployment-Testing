terraform {
  required_version = ">= 1.7.0"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

data "azurerm_storage_account" "backend" {
  name                = var.backend_storage_account_name
  resource_group_name = var.backend_resource_group_name
}

data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.blob_private_dns_resource_group_name
}

data "azurerm_virtual_network" "jumpbox" {
  name                = var.jumpbox_vnet_name
  resource_group_name = var.jumpbox_resource_group_name
}

data "azurerm_virtual_network" "lz" {
  name                = var.lz_vnet_name
  resource_group_name = var.lz_resource_group_name
}

data "azurerm_subnet" "shared_services" {
  name                 = var.lz_subnet_name
  virtual_network_name = var.lz_vnet_name
  resource_group_name  = var.lz_resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "jumpbox_blob" {
  name                  = "backend-jumpbox-blob-link"
  resource_group_name   = data.azurerm_private_dns_zone.blob.resource_group_name
  private_dns_zone_name = data.azurerm_private_dns_zone.blob.name
  virtual_network_id    = data.azurerm_virtual_network.jumpbox.id
  registration_enabled  = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_private_endpoint" "backend_blob" {
  name                = "pe-${var.backend_storage_account_name}-blob"
  location            = data.azurerm_virtual_network.lz.location
  resource_group_name = var.backend_resource_group_name
  subnet_id           = data.azurerm_subnet.shared_services.id

  private_service_connection {
    name                           = "psc-backend-blob"
    private_connection_resource_id = data.azurerm_storage_account.backend.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "backend-blob"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blob.id]
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "backend_blob_hostname" {
  value = "${data.azurerm_storage_account.backend.name}.blob.core.windows.net"
}

output "backend_private_ip" {
  value = azurerm_private_endpoint.backend_blob.private_service_connection[0].private_ip_address
}

output "backend_private_endpoint_id" {
  value = azurerm_private_endpoint.backend_blob.id
}
