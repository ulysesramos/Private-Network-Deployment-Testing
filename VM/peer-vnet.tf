resource "azurerm_resource_group" "networking" {
  name     = "rg-${local.name_prefix}-networking"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "peered_vnet" {
  name                = "vnet-${local.name_prefix}-peer"
  location            = azurerm_resource_group.networking.location
  resource_group_name = azurerm_resource_group.networking.name
  address_space       = [var.peered_vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "peered_subnet" {
  name                 = "snet-${local.name_prefix}-peer"
  resource_group_name  = azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.peered_vnet.name
  address_prefixes     = [var.peered_subnet_cidr]
}

resource "azurerm_virtual_network_peering" "peer_to_private" {
  name                         = "peer-peer-to-private"
  resource_group_name          = azurerm_resource_group.networking.name
  virtual_network_name         = azurerm_virtual_network.peered_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.private_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
