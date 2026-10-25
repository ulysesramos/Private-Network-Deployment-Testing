mock_provider "azurerm" {
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

variables {
  subscription_id                     = "00000000-0000-0000-0000-000000000001"
  environment                         = "test"
  lz_network_resource_group_name      = "rg-networking"
  lz_vnet_name                        = "vnet-lz"
  lz_subnet_name                      = "snet-lz"
  jumpbox_network_resource_group_name = "rg-jumpbox"
  jumpbox_vnet_name                   = "vnet-jumpbox"
  key_vault_name                      = "kv-pndt-test"
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
