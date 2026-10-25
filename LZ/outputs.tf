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
