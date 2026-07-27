locals {
  name_prefix = "pndt-${var.environment}"
  common_tags = {
    Environment = var.environment
    Workload    = "private-network-deployment-testing"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_resource_group" "resource_group" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-${local.name_prefix}-vm"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "bootdiag" {
  name                     = "st${replace(local.name_prefix, "-", "")}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}

resource "azurerm_windows_virtual_machine" "deployment_tester" {
  name                  = "vm-${local.name_prefix}-iac"
  computer_name         = substr(replace("vm-${local.name_prefix}", "-", ""), 0, 15)
  location              = azurerm_resource_group.resource_group.location
  resource_group_name   = azurerm_resource_group.resource_group.name
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  size                  = var.vm_size
  admin_username        = var.vm_admin_username
  admin_password        = var.vm_admin_password
  tags                  = local.common_tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.bootdiag.primary_blob_endpoint
  }
}

resource "azurerm_virtual_machine_extension" "iac_tools" {
  name                 = "InstallIaCTools"
  virtual_machine_id   = azurerm_windows_virtual_machine.deployment_tester.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"$ProgressPreference='SilentlyContinue'; winget install --silent --accept-source-agreements --accept-package-agreements Microsoft.AzureCLI; winget install --silent --accept-source-agreements --accept-package-agreements Microsoft.PowerShell; winget install --silent --accept-source-agreements --accept-package-agreements Hashicorp.Terraform; winget install --silent --accept-source-agreements --accept-package-agreements Git.Git; az bicep install\""
  })
}
