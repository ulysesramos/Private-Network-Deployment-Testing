locals {
  service_dns_zones = {
    blob      = "privatelink.blob.core.windows.net"
    dfs       = "privatelink.dfs.core.windows.net"
    cosmos    = "privatelink.documents.azure.com"
    search    = "privatelink.search.windows.net"
    cognitive = "privatelink.cognitiveservices.azure.com"
    foundry   = "privatelink.services.ai.azure.com"
    openai    = "privatelink.openai.azure.com"
  }
  service_dns_links = {
    for pair in setproduct(keys(local.service_dns_zones), ["lz", "jumpbox"]) :
    "${pair[0]}-${pair[1]}" => {
      zone_key = pair[0]
      vnet_id  = pair[1] == "lz" ? data.azurerm_virtual_network.lz.id : data.azurerm_virtual_network.jumpbox.id
    }
  }
  service_endpoints = merge(
    {
      for key in keys(local.storage_accounts) : "storage-${key}-blob" => {
        resource_id = azurerm_storage_account.services[key].id
        subresource = "blob"
        zone_ids    = [azurerm_private_dns_zone.services["blob"].id]
      }
    },
    {
      for key in local.projects : "cosmos-${key}" => {
        resource_id = azurerm_cosmosdb_account.projects[key].id
        subresource = "Sql"
        zone_ids    = [azurerm_private_dns_zone.services["cosmos"].id]
      }
    },
    {
      datalake-dfs = {
        resource_id = azurerm_storage_account.services["datalake"].id
        subresource = "dfs"
        zone_ids    = [azurerm_private_dns_zone.services["dfs"].id]
      }
      key-vault-ga = {
        resource_id = azurerm_key_vault.ga.id
        subresource = "vault"
        zone_ids    = [azurerm_private_dns_zone.key_vault.id]
      }
      search = {
        resource_id = azurerm_search_service.shared.id
        subresource = "searchService"
        zone_ids    = [azurerm_private_dns_zone.services["search"].id]
      }
      foundry = {
        resource_id = azurerm_cognitive_account.foundry.id
        subresource = "account"
        zone_ids = [
          azurerm_private_dns_zone.services["cognitive"].id,
          azurerm_private_dns_zone.services["foundry"].id,
          azurerm_private_dns_zone.services["openai"].id,
        ]
      }
    }
  )
}

resource "azurerm_private_dns_zone" "services" {
  for_each = local.service_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.lz.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "services" {
  for_each = local.service_dns_links

  name                  = each.key
  resource_group_name   = azurerm_resource_group.lz.name
  private_dns_zone_name = azurerm_private_dns_zone.services[each.value.zone_key].name
  virtual_network_id    = each.value.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "services" {
  for_each = local.service_endpoints

  name                = "pe-${local.service_prefix}-${each.key}"
  location            = azurerm_resource_group.lz.location
  resource_group_name = azurerm_resource_group.lz.name
  subnet_id           = data.azurerm_subnet.lz.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "private-dns"
    private_dns_zone_ids = each.value.zone_ids
  }
}
