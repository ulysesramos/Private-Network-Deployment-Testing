variable "subscription_id" {
  description = "Subscription containing the existing jump-box and LZ networks."
  type        = string
}

variable "environment" {
  description = "Environment used to name and tag the LZ resource group."
  type        = string
  default     = "prod"
}

variable "lz_network_resource_group_name" {
  description = "Resource group containing the existing LZ VNet."
  type        = string
}

variable "lz_vnet_name" {
  description = "Existing peered VNet used as the LZ."
  type        = string
}

variable "lz_subnet_name" {
  description = "Existing LZ subnet in which to create the private endpoint."
  type        = string
}

variable "jumpbox_network_resource_group_name" {
  description = "Resource group containing the existing jump-box VNet."
  type        = string
}

variable "jumpbox_vnet_name" {
  description = "Existing jump-box VNet that needs private DNS resolution."
  type        = string
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name: 3-24 alphanumeric characters or hyphens."
  type        = string

  validation {
    condition = (
      can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name)) &&
      !strcontains(var.key_vault_name, "--")
    )
    error_message = "Use 3-24 characters, start with a letter, end with a letter or digit, and do not use consecutive hyphens."
  }
}

variable "key_vault_private_dns_zone_name" {
  description = "Private DNS zone for the target cloud. Azure Government uses privatelink.vaultcore.usgovcloudapi.net."
  type        = string
  default     = "privatelink.vaultcore.azure.net"
}
