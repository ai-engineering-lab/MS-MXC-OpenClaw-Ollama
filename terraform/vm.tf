resource "azurerm_windows_virtual_machine" "main" {
  name                = "${local.base_name}-vm"
  computer_name       = "mxc-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  license_type        = var.license_type
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  os_disk {
    name                 = "${local.base_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.windows_image.publisher
    offer     = var.windows_image.offer
    sku       = var.windows_image.sku
    version   = var.windows_image.version
  }

  additional_capabilities {
    ultra_ssd_enabled = false
  }

  # Required for WSL2 / future Hyper-V and micro-VM MXC backends on Dsv5.
  vtpm_enabled           = true
  extensions_time_budget = "PT2H"

  timezone = "UTC"
}

resource "azurerm_virtual_machine_extension" "bootstrap" {
  count = var.run_bootstrap_extension ? 1 : 0

  name                       = "bootstrap-openclaw-mxc"
  virtual_machine_id         = azurerm_windows_virtual_machine.main.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = [azurerm_storage_blob.bootstrap[0].url]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1 -NodeVersion ${var.node_version} -MxcGitRepo \"${var.mxc_git_repo}\" -MxcGitRef \"${var.mxc_git_ref}\" -OpenClawPackage \"${var.openclaw_npm_package}\" -GatewayPort ${var.openclaw_gateway_port} -OllamaModel \"${var.ollama_model}\" -OllamaVersion ${var.ollama_version} -GitForWindowsVersion ${var.git_for_windows_version} -InstallOllama \"${lower(tostring(var.install_ollama))}\" -DisableControlUiDeviceAuth \"${lower(tostring(var.openclaw_control_ui_disable_device_auth))}\""
  })

  timeouts {
    create = "2h"
    delete = "30m"
  }

  depends_on = [
    azurerm_storage_blob.bootstrap,
  ]
}
