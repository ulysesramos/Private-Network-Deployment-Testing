mock_provider "azurerm" {}

override_data {
  target = data.azurerm_storage_account.backend
  values = {
    id   = "/subscriptions/92ade028-994d-424c-a639-48e33b16e332/resourceGroups/pndt-terraform-state/providers/Microsoft.Storage/storageAccounts/pndtterrastate"
    name = "pndtterrastate"
  }
}

override_data {
  target = data.azurerm_private_dns_zone.blob
  values = {
    id                  = "/subscriptions/92ade028-994d-424c-a639-48e33b16e332/resourceGroups/rg-pndt-prod-storage/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    name                = "privatelink.blob.core.windows.net"
    resource_group_name = "rg-pndt-prod-storage"
  }
}

override_data {
  target = data.azurerm_virtual_network.jumpbox
  values = {
    id = "/subscriptions/92ade028-994d-424c-a639-48e33b16e332/resourceGroups/rg-pndt-prod/providers/Microsoft.Network/virtualNetworks/vnet-pndt-prod-private"
  }
}

override_data {
  target = data.azurerm_virtual_network.lz
  values = {
    location = "westus3"
  }
}

override_data {
  target = data.azurerm_subnet.shared_services
  values = {
    id = "/subscriptions/92ade028-994d-424c-a639-48e33b16e332/resourceGroups/rg-pndt-prod-networking/providers/Microsoft.Network/virtualNetworks/vnet-pndt-prod-peer/subnets/snet-pndt-prod-peer"
  }
}

run "private_backend_path" {
  command = plan

  assert {
    condition = (
      azurerm_private_endpoint.backend_blob.subnet_id == data.azurerm_subnet.shared_services.id &&
      azurerm_private_endpoint.backend_blob.location == data.azurerm_virtual_network.lz.location &&
      azurerm_private_endpoint.backend_blob.private_service_connection[0].private_connection_resource_id == data.azurerm_storage_account.backend.id &&
      azurerm_private_endpoint.backend_blob.private_service_connection[0].subresource_names == tolist(["blob"]) &&
      !azurerm_private_endpoint.backend_blob.private_service_connection[0].is_manual_connection &&
      azurerm_private_endpoint.backend_blob.private_dns_zone_group[0].private_dns_zone_ids == tolist([data.azurerm_private_dns_zone.blob.id])
    )
    error_message = "Backend connectivity must target the existing account's Blob service through shared services and the existing DNS zone."
  }

  assert {
    condition = (
      azurerm_private_dns_zone_virtual_network_link.jumpbox_blob.virtual_network_id == data.azurerm_virtual_network.jumpbox.id &&
      azurerm_private_dns_zone_virtual_network_link.jumpbox_blob.private_dns_zone_name == data.azurerm_private_dns_zone.blob.name &&
      !azurerm_private_dns_zone_virtual_network_link.jumpbox_blob.registration_enabled
    )
    error_message = "The existing Blob zone must resolve from the jump-box VNet without auto-registration."
  }
}
