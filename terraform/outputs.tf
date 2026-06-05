output "resource_group_name" {
  description = "Name of the deployed resource group."
  value       = azurerm_resource_group.main.name
}

output "vm_name" {
  description = "Name of the Windows VM."
  value       = azurerm_windows_virtual_machine.main.name
}

output "vm_private_ip" {
  description = "Private IP address of the VM."
  value       = azurerm_network_interface.vm.private_ip_address
}

output "vm_public_ip" {
  description = "Public IP address of the VM (null when enable_public_ip is false)."
  value       = var.enable_public_ip ? azurerm_public_ip.vm[0].ip_address : null
}

output "rdp_connection" {
  description = "RDP connection string for Remote Desktop."
  value       = var.enable_public_ip ? "mstsc /v:${azurerm_public_ip.vm[0].ip_address}" : "Use Azure Bastion or private connectivity; public IP disabled."
}

output "openclaw_gateway_url" {
  description = "Default OpenClaw gateway URL once bootstrap completes."
  value       = var.enable_public_ip ? "http://${azurerm_public_ip.vm[0].ip_address}:${var.openclaw_gateway_port}" : "http://${azurerm_network_interface.vm.private_ip_address}:${var.openclaw_gateway_port}"
}

output "bootstrap_log_path" {
  description = "Path to the bootstrap log on the VM."
  value       = "C:\\bootstrap\\bootstrap.log"
}

output "ollama_model" {
  description = "Ollama model configured for OpenClaw (null when install_ollama is false)."
  value       = var.install_ollama ? var.ollama_model : null
}

output "pinned_dependencies" {
  description = "Pinned runtime dependency versions deployed by bootstrap. See dependencies.lock.json."
  value = {
    mxc_git_repo      = var.mxc_git_repo
    mxc_git_ref       = var.mxc_git_ref
    mxc_sdk_package   = "@microsoft/mxc-sdk"
    openclaw          = var.openclaw_version
    openclaw_npm_spec = var.openclaw_npm_package
    node              = var.node_version
    ollama            = var.ollama_version
    git_for_windows   = var.git_for_windows_version
    ollama_model      = var.install_ollama ? var.ollama_model : null
  }
}

output "next_steps" {
  description = "Post-deploy configuration required on the VM."
  value       = <<-EOT
    1. RDP to the VM and review C:\bootstrap\bootstrap.log
    2. Read gateway URL + token from C:\openclaw\gateway-access.txt
    3. Open the Control UI at the gateway URL from your browser and paste the token
    4. When install_ollama is true, confirm model pull in C:\bootstrap\ollama-pull.log (ollama/${var.ollama_model})
    5. OpenClaw uses local Ollama at http://127.0.0.1:11434 once the model pull completes
    6. Configure MXC processcontainer backend per OpenClaw + @microsoft/mxc-sdk docs
  EOT
}
