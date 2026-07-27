variable "subscription_id" {
  description = "Azure subscription ID used for deployment."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment tag and naming suffix (for example: dev, test, prod)."
  type        = string
  default     = "test"
}

variable "vm_admin_username" {
  description = "Admin username for the Windows VM."
  type        = string
  default     = "azureadmin"
}

variable "vm_admin_password" {
  description = "Admin password for the Windows VM."
  type        = string
  sensitive   = true
}

variable "vm_size" {
  description = "VM SKU."
  type        = string
  default     = "Standard_B2s"
}

variable "private_vnet_cidr" {
  description = "CIDR block for the VM and Bastion VNet."
  type        = string
  default     = "10.40.0.0/16"
}

variable "vm_subnet_cidr" {
  description = "CIDR block for VM subnet."
  type        = string
  default     = "10.40.1.0/24"
}

variable "bastion_subnet_cidr" {
  description = "CIDR block for Azure Bastion subnet."
  type        = string
  default     = "10.40.2.0/26"
}

variable "peered_vnet_cidr" {
  description = "CIDR block for peered private network used for deployment testing."
  type        = string
  default     = "10.50.0.0/16"
}

variable "peered_subnet_cidr" {
  description = "CIDR block for peered VNet subnet."
  type        = string
  default     = "10.50.1.0/24"
}
