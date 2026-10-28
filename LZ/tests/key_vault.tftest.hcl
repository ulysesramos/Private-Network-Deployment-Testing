mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.Storage/storageAccounts/stpndtlztest01"
      primary_blob_endpoint = "https://stpndtlztest01.blob.core.windows.net/"
    }
  }

  mock_resource "azurerm_cosmosdb_account" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-test"
      endpoint = "https://cosmos-test.documents.azure.com:443/"
    }
  }

  mock_resource "azurerm_search_service" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.Search/searchServices/search-test"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-lz/subnets/foundry-egress"
    }
  }

  mock_resource "azurerm_cognitive_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.CognitiveServices/accounts/foundry-test"
    }
  }

  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.KeyVault/vaults/kv-pndt-test"
      vault_uri = "https://kv-pndt-test.vault.azure.net/"
    }
  }

  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    }
  }
}

mock_provider "azapi" {}
mock_provider "time" {}

override_resource {
  target = azapi_resource.foundry_project["ga"]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.CognitiveServices/accounts/foundry-test/projects/GA"
    output = {
      identity = { principalId = "00000000-0000-0000-0000-000000000004" }
    }
  }
}

override_resource {
  target = azapi_resource.foundry_project["rec"]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-pndt-test-lz/providers/Microsoft.CognitiveServices/accounts/foundry-test/projects/REC"
    output = {
      identity = { principalId = "00000000-0000-0000-0000-000000000005" }
    }
  }
}

override_data {
  target = data.azurerm_client_config.current
  values = {
    tenant_id = "00000000-0000-0000-0000-000000000002"
    object_id = "00000000-0000-0000-0000-000000000003"
  }
}

override_data {
  target = data.azurerm_virtual_network.lz
  values = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-lz"
    name                = "vnet-lz"
    resource_group_name = "rg-networking"
    location            = "westus3"
    address_space       = ["10.50.0.0/16"]
    subnets             = ["snet-lz"]
  }
}

override_data {
  target = data.azurerm_virtual_network.jumpbox
  values = {
    id                  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-jumpbox/providers/Microsoft.Network/virtualNetworks/vnet-jumpbox"
    name                = "vnet-jumpbox"
    resource_group_name = "rg-jumpbox"
    location            = "westus3"
  }
}

override_data {
  target = data.azurerm_subnet.lz
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-lz/subnets/snet-lz"
  }
}

override_data {
  target = data.azurerm_subnet.existing_lz["snet-lz"]
  values = {
    address_prefixes = ["10.50.1.0/24"]
  }
}

variables {
  subscription_id                     = "00000000-0000-0000-0000-000000000001"
  environment                         = "test"
  lz_network_resource_group_name      = "rg-networking"
  lz_vnet_name                        = "vnet-lz"
  lz_subnet_name                      = "snet-lz"
  jumpbox_network_resource_group_name = "rg-jumpbox"
  jumpbox_vnet_name                   = "vnet-jumpbox"
  key_vault_name                      = "kv-pndt-test"
  resource_suffix                     = "test01"
}

run "private_key_vault" {
  command = apply

  assert {
    condition = (
      azurerm_key_vault.lz.rbac_authorization_enabled &&
      !azurerm_key_vault.lz.public_network_access_enabled &&
      azurerm_key_vault.lz.purge_protection_enabled &&
      azurerm_key_vault.lz.soft_delete_retention_days == 90 &&
      azurerm_key_vault.lz.network_acls[0].bypass == "None" &&
      azurerm_key_vault.lz.network_acls[0].default_action == "Deny"
    )
    error_message = "The vault must use RBAC, private-only access, and protected soft deletion."
  }

  assert {
    condition = (
      azurerm_private_endpoint.key_vault.subnet_id == data.azurerm_subnet.lz.id &&
      azurerm_private_endpoint.key_vault.private_service_connection[0].subresource_names == tolist(["vault"]) &&
      !azurerm_private_endpoint.key_vault.private_service_connection[0].is_manual_connection &&
      azurerm_private_endpoint.key_vault.private_dns_zone_group[0].private_dns_zone_ids == tolist([azurerm_private_dns_zone.key_vault.id])
    )
    error_message = "The vault endpoint must use the existing LZ subnet and its DNS zone group."
  }

  assert {
    condition = (
      length(azurerm_private_dns_zone_virtual_network_link.key_vault) == 2 &&
      azurerm_private_dns_zone_virtual_network_link.key_vault["lz"].virtual_network_id == data.azurerm_virtual_network.lz.id &&
      azurerm_private_dns_zone_virtual_network_link.key_vault["jumpbox"].virtual_network_id == data.azurerm_virtual_network.jumpbox.id &&
      alltrue([for link in azurerm_private_dns_zone_virtual_network_link.key_vault : !link.registration_enabled])
    )
    error_message = "The same private DNS zone must be linked to both VNets without auto-registration."
  }

  assert {
    condition = (
      azurerm_role_assignment.deployer_secrets.principal_id == data.azurerm_client_config.current.object_id &&
      azurerm_role_assignment.deployer_secrets.role_definition_name == "Key Vault Secrets Officer" &&
      azurerm_role_assignment.deployer_secrets.scope == azurerm_key_vault.lz.id
    )
    error_message = "The Terraform caller must receive secret-management permissions scoped to the vault."
  }
}

run "invalid_vault_name" {
  command = plan

  variables {
    key_vault_name = "invalid--vault"
  }

  expect_failures = [var.key_vault_name]
}

run "private_services_and_project_wiring" {
  command = apply

  assert {
    condition = (
      length(azurerm_storage_account.services) == 4 &&
      alltrue([for account in azurerm_storage_account.services :
        !account.public_network_access_enabled &&
        !account.shared_access_key_enabled &&
        !account.allow_nested_items_to_be_public &&
        account.network_rules[0].default_action == "Deny" &&
        account.min_tls_version == "TLS1_2"
      ]) &&
      azurerm_storage_account.services["datalake"].is_hns_enabled &&
      alltrue([for key in ["shared", "ga", "rec"] : !azurerm_storage_account.services[key].is_hns_enabled])
    )
    error_message = "All four storage accounts must be private and Entra-only; only Data Lake enables HNS."
  }

  assert {
    condition = (
      length(azurerm_cosmosdb_account.projects) == 2 &&
      alltrue([for account in azurerm_cosmosdb_account.projects :
        account.kind == "GlobalDocumentDB" &&
        !account.public_network_access_enabled &&
        !account.local_authentication_enabled
      ]) &&
      !azurerm_search_service.shared.public_network_access_enabled &&
      !azurerm_search_service.shared.local_authentication_enabled &&
      azurerm_key_vault.ga.rbac_authorization_enabled &&
      !azurerm_key_vault.ga.public_network_access_enabled &&
      azurerm_key_vault.ga.purge_protection_enabled
    )
    error_message = "Cosmos GA/REC, shared Search, and GA Key Vault must use private access and identity-based authorization."
  }

  assert {
    condition = (
      length(azurerm_private_endpoint.services) == 10 &&
      alltrue([for endpoint in azurerm_private_endpoint.services :
        endpoint.subnet_id == data.azurerm_subnet.lz.id &&
        !endpoint.private_service_connection[0].is_manual_connection
      ]) &&
      azurerm_private_endpoint.services["datalake-dfs"].private_service_connection[0].subresource_names == tolist(["dfs"]) &&
      azurerm_private_endpoint.services["storage-datalake-blob"].private_service_connection[0].subresource_names == tolist(["blob"]) &&
      length(azurerm_private_endpoint.services["foundry"].private_dns_zone_group[0].private_dns_zone_ids) == 3 &&
      length(azurerm_private_dns_zone.services) == 7 &&
      length(azurerm_private_dns_zone_virtual_network_link.services) == 14 &&
      alltrue([for key, link in azurerm_private_dns_zone_virtual_network_link.services :
        link.virtual_network_id == (endswith(key, "-lz") ? data.azurerm_virtual_network.lz.id : data.azurerm_virtual_network.jumpbox.id) &&
        !link.registration_enabled
      ])
    )
    error_message = "All ten new endpoints must use shared services; Data Lake needs Blob+DFS and every service zone must link to both VNets."
  }

  assert {
    condition = (
      azurerm_subnet.foundry_egress.delegation[0].service_delegation[0].name == "Microsoft.App/environments" &&
      azurerm_cognitive_account.foundry.kind == "AIServices" &&
      azurerm_cognitive_account.foundry.project_management_enabled &&
      !azurerm_cognitive_account.foundry.public_network_access_enabled &&
      !azurerm_cognitive_account.foundry.local_auth_enabled &&
      azurerm_cognitive_account.foundry.network_injection[0].subnet_id == azurerm_subnet.foundry_egress.id &&
      azurerm_cognitive_account.foundry.network_injection[0].scenario == "agent" &&
      length(azapi_resource.foundry_project) == 2
    )
    error_message = "Foundry must use its dedicated delegated subnet for agent egress and host two private projects."
  }

  assert {
    condition = (
      length(azapi_resource.project_connection) == 6 &&
      alltrue([for key in ["ga", "rec"] :
        azapi_resource.project_connection["${key}-storage"].name == azurerm_storage_account.services[key].name &&
        azapi_resource.project_connection["${key}-cosmos"].name == azurerm_cosmosdb_account.projects[key].name &&
        azapi_resource.project_connection["${key}-search"].name == azurerm_search_service.shared.name &&
        azapi_resource.project_connection["${key}-storage"].parent_id == azapi_resource.foundry_project[key].id &&
        azapi_resource.project_connection["${key}-cosmos"].parent_id == azapi_resource.foundry_project[key].id &&
        azapi_resource.project_connection["${key}-search"].parent_id == azapi_resource.foundry_project[key].id &&
        azapi_resource.project_capability_host[key].body.properties.storageConnections == [azurerm_storage_account.services[key].name] &&
        azapi_resource.project_capability_host[key].body.properties.threadStorageConnections == [azurerm_cosmosdb_account.projects[key].name] &&
        azapi_resource.project_capability_host[key].body.properties.vectorStoreConnections == [azurerm_search_service.shared.name]
      ]) &&
      alltrue([for connection in azapi_resource.project_connection : connection.body.properties.authType == "AAD"])
    )
    error_message = "GA and REC must each connect to their own Storage/Cosmos, share Search, and wire those connections into capability hosts using AAD."
  }

  assert {
    condition = alltrue([for key in ["ga", "rec"] :
      azurerm_role_assignment.project_services["${key}-storage"].scope == azurerm_storage_account.services[key].id &&
      azurerm_role_assignment.project_services["${key}-storage"].role_definition_name == "Storage Blob Data Owner" &&
      azurerm_role_assignment.project_services["${key}-cosmos"].scope == azurerm_cosmosdb_account.projects[key].id &&
      azurerm_role_assignment.project_services["${key}-search-service"].scope == azurerm_search_service.shared.id &&
      azurerm_role_assignment.project_services["${key}-search-data"].role_definition_name == "Search Index Data Contributor" &&
      azurerm_role_assignment.project_foundry[key].scope == azurerm_cognitive_account.foundry.id &&
      azurerm_role_assignment.project_foundry[key].principal_id == azapi_resource.foundry_project[key].output.identity.principalId &&
      endswith(azurerm_role_assignment.project_foundry[key].role_definition_id, "/53ca6127-db72-4b80-b1b0-d745d6d5456d") &&
      azurerm_cosmosdb_sql_role_assignment.project_data[key].principal_id == azapi_resource.foundry_project[key].output.identity.principalId &&
      azurerm_role_assignment.project_services["${key}-storage"].principal_id == azapi_resource.foundry_project[key].output.identity.principalId
    ])
    error_message = "Project identities must receive matching account-scoped Storage/Cosmos and shared Search permissions."
  }
}

run "egress_outside_lz" {
  command = plan

  variables {
    foundry_egress_subnet_cidr = "10.60.2.0/24"
  }

  expect_failures = [azurerm_subnet.foundry_egress]
}

run "egress_overlaps_shared_services" {
  command = plan

  variables {
    foundry_egress_subnet_cidr = "10.50.1.0/24"
  }

  expect_failures = [azurerm_subnet.foundry_egress]
}
