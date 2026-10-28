output "resource_group_name" {
  description = "Resource group owned by this LZ deployment."
  value       = azurerm_resource_group.lz.name
}

output "key_vault_name" {
  description = "Name of the private Key Vault."
  value       = azurerm_key_vault.lz.name
}

output "key_vault_uri" {
  description = "Use this normal vault URI; DNS resolves it to the private endpoint."
  value       = azurerm_key_vault.lz.vault_uri
}

output "key_vault_private_ip" {
  description = "Expected final A-record address when resolving the vault from the jump box."
  value       = azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address
}

output "deployer_object_id" {
  description = "Terraform identity granted Key Vault Secrets Officer on this vault."
  value       = data.azurerm_client_config.current.object_id
}

output "storage_account_names" {
  description = "Shared, GA, REC, and HNS-enabled Data Lake storage accounts."
  value       = { for key, account in azurerm_storage_account.services : key => account.name }
}

output "key_vault_ga_uri" {
  description = "GA vault URI, resolved privately through the existing shared vault DNS zone."
  value       = azurerm_key_vault.ga.vault_uri
}

output "cosmos_account_names" {
  description = "Separate NoSQL accounts associated with GA and REC."
  value       = { for key, account in azurerm_cosmosdb_account.projects : key => account.name }
}

output "search_endpoint" {
  description = "AI Search endpoint shared by both Foundry projects."
  value       = "https://${azurerm_search_service.shared.name}.search.windows.net"
}

output "foundry_name" {
  description = "Private Foundry account hosting the two Standard Agent projects."
  value       = azurerm_cognitive_account.foundry.name
}

output "foundry_projects" {
  description = "Project resource IDs and project-managed identities."
  value = {
    for key, project in azapi_resource.foundry_project : key => {
      id           = project.id
      principal_id = project.output.identity.principalId
    }
  }
}

output "foundry_egress_subnet_id" {
  description = "Dedicated Microsoft.App/environments delegated subnet; never used for private endpoints."
  value       = azurerm_subnet.foundry_egress.id
}

output "service_private_endpoints" {
  description = "Resource IDs and primary private IPs for the new shared-services endpoints."
  value = {
    for key, endpoint in azurerm_private_endpoint.services : key => {
      id         = endpoint.id
      private_ip = endpoint.private_service_connection[0].private_ip_address
    }
  }

}

output "private_service_uris" {
  description = "Service URIs to resolve and test on TCP 443 from the jump box."
  value = merge(
    { for key, account in azurerm_storage_account.services : "storage-${key}-blob" => account.primary_blob_endpoint },
    { for key, account in azurerm_cosmosdb_account.projects : "cosmos-${key}" => account.endpoint },
    {
      key-vault    = azurerm_key_vault.lz.vault_uri
      key-vault-ga = azurerm_key_vault.ga.vault_uri
      datalake-dfs = azurerm_storage_account.services["datalake"].primary_dfs_endpoint
      search       = "https://${azurerm_search_service.shared.name}.search.windows.net"
      cognitive    = "https://${azurerm_cognitive_account.foundry.custom_subdomain_name}.cognitiveservices.azure.com"
      foundry      = "https://${azurerm_cognitive_account.foundry.custom_subdomain_name}.services.ai.azure.com"
      openai       = "https://${azurerm_cognitive_account.foundry.custom_subdomain_name}.openai.azure.com"
    }
  )
}
