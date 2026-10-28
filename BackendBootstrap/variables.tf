variable "subscription_id" {
  type    = string
  default = "92ade028-994d-424c-a639-48e33b16e332"
}

variable "backend_storage_account_name" {
  type    = string
  default = "pndtterrastate"
}

variable "backend_resource_group_name" {
  type    = string
  default = "pndt-terraform-state"
}

variable "blob_private_dns_resource_group_name" {
  type    = string
  default = "rg-pndt-prod-storage"
}

variable "jumpbox_vnet_name" {
  type    = string
  default = "vnet-pndt-prod-private"
}

variable "jumpbox_resource_group_name" {
  type    = string
  default = "rg-pndt-prod"
}

variable "lz_vnet_name" {
  type    = string
  default = "vnet-pndt-prod-peer"
}

variable "lz_resource_group_name" {
  type    = string
  default = "rg-pndt-prod-networking"
}

variable "lz_subnet_name" {
  type    = string
  default = "snet-pndt-prod-peer"
}
