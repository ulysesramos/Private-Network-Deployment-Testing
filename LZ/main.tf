locals {
  name_prefix = "pndt-${var.environment}-lz"
  common_tags = {
    Environment = var.environment
    Workload    = "private-network-deployment-testing"
    ManagedBy   = "terraform"
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "lz" {
  name                = var.lz_vnet_name
  resource_group_name = var.lz_network_resource_group_name
}

data "azurerm_subnet" "lz" {
  name                 = var.lz_subnet_name
  virtual_network_name = data.azurerm_virtual_network.lz.name
  resource_group_name  = data.azurerm_virtual_network.lz.resource_group_name
}

data "azurerm_virtual_network" "jumpbox" {
  name                = var.jumpbox_vnet_name
  resource_group_name = var.jumpbox_network_resource_group_name
}

resource "azurerm_resource_group" "lz" {
  name     = "rg-${local.name_prefix}"
  location = data.azurerm_virtual_network.lz.location
  tags     = local.common_tags
}

resource "azurerm_key_vault" "lz" {
  name                          = var.key_vault_name
  location                      = azurerm_resource_group.lz.location
  resource_group_name           = azurerm_resource_group.lz.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  tags                          = local.common_tags

  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = var.key_vault_private_dns_zone_name
  resource_group_name = azurerm_resource_group.lz.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  for_each = {
    lz      = data.azurerm_virtual_network.lz.id
    jumpbox = data.azurerm_virtual_network.jumpbox.id
  }

  name                  = "${each.key}-key-vault"
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-${var.key_vault_name}"
  location            = azurerm_resource_group.lz.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = data.azurerm_subnet.lz.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${var.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.lz.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "key-vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_role_assignment" "deployer_secrets" {
  scope                = azurerm_key_vault.lz.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
