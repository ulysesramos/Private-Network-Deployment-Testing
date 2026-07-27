resource "azurerm_virtual_network" "private_vnet" {
  name                = "vnet-${local.name_prefix}-private"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  address_space       = [var.private_vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "vm_subnet" {
  name                 = "snet-${local.name_prefix}-vm"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.private_vnet.name
  address_prefixes     = [var.vm_subnet_cidr]
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-${local.name_prefix}-vm"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-RDP-From-Bastion-Subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.bastion_subnet_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm_subnet_nsg" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_virtual_network_peering" "private_to_peer" {
  name                         = "peer-private-to-peer"
  resource_group_name          = azurerm_resource_group.resource_group.name
  virtual_network_name         = azurerm_virtual_network.private_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.peered_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
