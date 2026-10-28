data "azurerm_subnet" "existing_lz" {
  for_each = toset([
    for name in data.azurerm_virtual_network.lz.subnets : name
    if name != "snet-${local.name_prefix}-foundry-egress"
  ])

  name                 = each.key
  resource_group_name  = data.azurerm_virtual_network.lz.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.lz.name
}

locals {
  existing_subnet_prefixes = flatten([for subnet in data.azurerm_subnet.existing_lz : subnet.address_prefixes])
  ipv4_ranges = {
    for cidr in toset(concat(
      data.azurerm_virtual_network.lz.address_space,
      local.existing_subnet_prefixes,
      [var.foundry_egress_subnet_cidr],
      )) : cidr => {
      first = sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
      last  = sum([for i, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - i)])
    } if can(cidrnetmask(cidr))
  }
  egress_range = local.ipv4_ranges[var.foundry_egress_subnet_cidr]
}

resource "azurerm_subnet" "foundry_egress" {
  name                 = "snet-${local.name_prefix}-foundry-egress"
  resource_group_name  = data.azurerm_virtual_network.lz.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.lz.name
  address_prefixes     = [var.foundry_egress_subnet_cidr]

  lifecycle {
    precondition {
      condition = anytrue([
        for cidr in data.azurerm_virtual_network.lz.address_space :
        try(local.ipv4_ranges[cidr].first <= local.egress_range.first && local.ipv4_ranges[cidr].last >= local.egress_range.last, false)
      ])
      error_message = "The Foundry egress subnet must be entirely inside the existing LZ VNet."
    }
    precondition {
      condition = alltrue([
        for cidr in local.existing_subnet_prefixes :
        try(local.ipv4_ranges[cidr].last < local.egress_range.first || local.ipv4_ranges[cidr].first > local.egress_range.last, true)
      ])
      error_message = "The Foundry egress subnet overlaps an existing LZ subnet."
    }
  }

  delegation {
    name = "foundry-agents"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_cognitive_account" "foundry" {
  name                          = "aif-${local.service_prefix}"
  location                      = azurerm_resource_group.lz.location
  resource_group_name           = azurerm_resource_group.lz.name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = "aif-${local.service_prefix}"
  project_management_enabled    = true
  public_network_access_enabled = false
  local_auth_enabled            = false
  tags                          = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }

  network_injection {
    scenario  = "agent"
    subnet_id = azurerm_subnet.foundry_egress.id
  }
}

resource "azapi_resource" "foundry_project" {
  for_each = local.projects

  type      = "Microsoft.CognitiveServices/accounts/projects@2026-05-01"
  name      = upper(each.key)
  parent_id = azurerm_cognitive_account.foundry.id
  location  = azurerm_resource_group.lz.location
  tags      = merge(local.common_tags, { Association = each.key })
  body = {
    identity = { type = "SystemAssigned" }
    properties = {
      displayName = upper(each.key)
      description = "${upper(each.key)} private Standard Agent project"
    }
  }
  response_export_values = ["identity.principalId", "properties.internalId", "properties.endpoints"]

  depends_on = [
    azurerm_private_endpoint.services,
    azurerm_private_dns_zone_virtual_network_link.services,
  ]
}

locals {
  project_connections = merge(
    {
      for key in local.projects : "${key}-storage" => {
        project     = key
        name        = azurerm_storage_account.services[key].name
        category    = "AzureStorageAccount"
        target      = azurerm_storage_account.services[key].primary_blob_endpoint
        resource_id = azurerm_storage_account.services[key].id
      }
    },
    {
      for key in local.projects : "${key}-cosmos" => {
        project     = key
        name        = azurerm_cosmosdb_account.projects[key].name
        category    = "CosmosDb"
        target      = azurerm_cosmosdb_account.projects[key].endpoint
        resource_id = azurerm_cosmosdb_account.projects[key].id
      }
    },
    {
      for key in local.projects : "${key}-search" => {
        project = key
        # Preserve GA's deployed connection; REC needs a distinct backing-workspace name.
        name        = key == "ga" ? azurerm_search_service.shared.name : "${azurerm_search_service.shared.name}-${key}"
        category    = "CognitiveSearch"
        target      = "https://${azurerm_search_service.shared.name}.search.windows.net"
        resource_id = azurerm_search_service.shared.id
      }
    }
  )
  project_roles = merge(
    {
      for key in local.projects : "${key}-storage" => {
        project = key
        scope   = azurerm_storage_account.services[key].id
        role    = "Storage Blob Data Owner"
      }
    },
    {
      for key in local.projects : "${key}-cosmos" => {
        project = key
        scope   = azurerm_cosmosdb_account.projects[key].id
        role    = "Cosmos DB Operator"
      }
    },
    {
      for key in local.projects : "${key}-search-data" => {
        project = key
        scope   = azurerm_search_service.shared.id
        role    = "Search Index Data Contributor"
      }
    },
    {
      for key in local.projects : "${key}-search-service" => {
        project = key
        scope   = azurerm_search_service.shared.id
        role    = "Search Service Contributor"
      }
    }
  )
}

resource "azapi_resource" "project_connection" {
  for_each = local.project_connections

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01"
  name      = each.value.name
  parent_id = azapi_resource.foundry_project[each.value.project].id
  body = {
    properties = {
      category = each.value.category
      target   = each.value.target
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = each.value.resource_id
        location   = azurerm_resource_group.lz.location
      }
    }
  }
}

resource "azurerm_role_assignment" "project_services" {
  for_each = local.project_roles

  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azapi_resource.foundry_project[each.value.project].output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_cosmosdb_sql_role_assignment" "project_data" {
  for_each = local.projects

  resource_group_name = azurerm_resource_group.lz.name
  account_name        = azurerm_cosmosdb_account.projects[each.key].name
  scope               = azurerm_cosmosdb_account.projects[each.key].id
  role_definition_id  = "${azurerm_cosmosdb_account.projects[each.key].id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.foundry_project[each.key].output.identity.principalId
}

resource "azurerm_role_assignment" "deployer_foundry" {
  for_each = local.projects

  scope              = azapi_resource.foundry_project[each.key].id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "project_foundry" {
  for_each = local.projects

  scope                            = azurerm_cognitive_account.foundry.id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azapi_resource.foundry_project[each.key].output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Capability provisioning uses the project identity; Azure RBAC is eventually consistent.
resource "time_sleep" "project_rbac" {
  for_each = local.projects

  create_duration = "120s"
  triggers = {
    principal_id = azapi_resource.foundry_project[each.key].output.identity.principalId
  }

  depends_on = [
    azurerm_role_assignment.project_services,
    azurerm_role_assignment.project_foundry,
    azurerm_cosmosdb_sql_role_assignment.project_data,
  ]
}

resource "azapi_resource" "project_capability_host" {
  for_each = local.projects

  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2026-05-01"
  name      = "agents"
  parent_id = azapi_resource.foundry_project[each.key].id
  body = {
    properties = {
      storageConnections       = [azapi_resource.project_connection["${each.key}-storage"].name]
      threadStorageConnections = [azapi_resource.project_connection["${each.key}-cosmos"].name]
      vectorStoreConnections   = [azapi_resource.project_connection["${each.key}-search"].name]
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  depends_on = [time_sleep.project_rbac]
}
