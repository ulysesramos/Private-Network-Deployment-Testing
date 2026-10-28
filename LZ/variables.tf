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
  description = "Existing LZ subnet used as shared services for all private endpoints."
  type        = string
}

variable "resource_suffix" {
  description = "Stable globally unique suffix for new service names; do not change after deployment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,8}$", var.resource_suffix))
    error_message = "Use 4-8 lowercase letters or digits."
  }
}

variable "foundry_egress_subnet_cidr" {
  description = "Unused RFC1918 /24 within the existing LZ VNet for Foundry agent egress."
  type        = string
  default     = "10.50.2.0/24"

  validation {
    condition = (
      can(cidrnetmask(var.foundry_egress_subnet_cidr)) &&
      can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.).*/24$", var.foundry_egress_subnet_cidr)) &&
      try(cidrhost(var.foundry_egress_subnet_cidr, 0), "") == split("/", var.foundry_egress_subnet_cidr)[0]
    )
    error_message = "Provide an RFC1918 IPv4 /24 subnet, inside the LZ VNet and not overlapping any existing subnet."
  }
}

variable "search_sku" {
  description = "Paid AI Search SKU supporting private endpoints; shared by GA and REC."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "standard2", "standard3"], var.search_sku)
    error_message = "Use standard, standard2, or standard3."
  }
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
