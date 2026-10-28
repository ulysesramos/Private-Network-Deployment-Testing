locals {
  service_prefix = "pndtlz${var.resource_suffix}"
  projects       = toset(["ga", "rec"])
  storage_accounts = {
    shared   = { hns = false }
    ga       = { hns = false }
    rec      = { hns = false }
    datalake = { hns = true }
  }
}

resource "azurerm_storage_account" "services" {
  for_each = local.storage_accounts

  name                            = "st${local.service_prefix}${each.key}"
  location                        = azurerm_resource_group.lz.location
  resource_group_name             = azurerm_resource_group.lz.name
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = each.value.hns
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  tags                            = merge(local.common_tags, { Association = each.key })

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }
}

resource "azurerm_key_vault" "ga" {
  name                          = "kv-${local.service_prefix}-ga"
  location                      = azurerm_resource_group.lz.location
  resource_group_name           = azurerm_resource_group.lz.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  tags                          = merge(local.common_tags, { Association = "ga" })

  network_acls {
    bypass         = "None"
    default_action = "Deny"
  }
}

resource "azurerm_cosmosdb_account" "projects" {
  for_each = local.projects

  name                          = "cosmos-${local.service_prefix}-${each.key}"
  location                      = azurerm_resource_group.lz.location
  resource_group_name           = azurerm_resource_group.lz.name
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  public_network_access_enabled = false
  local_authentication_enabled  = false
  minimal_tls_version           = "Tls12"
  tags                          = merge(local.common_tags, { Association = each.key })

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.lz.location
    failover_priority = 0
  }
}

resource "azurerm_search_service" "shared" {
  name                          = "srch-${local.service_prefix}"
  location                      = azurerm_resource_group.lz.location
  resource_group_name           = azurerm_resource_group.lz.name
  sku                           = var.search_sku
  replica_count                 = 1
  partition_count               = 1
  public_network_access_enabled = false
  local_authentication_enabled  = false
  tags                          = local.common_tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "deployer_ga_secrets" {
  scope                = azurerm_key_vault.ga.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_storage" {
  for_each = local.storage_accounts

  scope                = azurerm_storage_account.services[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
