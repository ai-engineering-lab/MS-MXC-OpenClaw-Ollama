variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use the CLI's default subscription."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "canadacentral"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "mxc-openclaw"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project = "mxc-openclaw"
    managed = "terraform"
  }
}

variable "vm_size" {
  description = "Azure VM size. Standard_D4s_v3 works on Azure for Students; D4s_v5 supports nested virtualization when quota allows."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "admin_username" {
  description = "Local administrator username for the Windows VM."
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Local administrator password. Must meet Azure Windows complexity requirements."
  type        = string
  sensitive   = true
}

variable "windows_image" {
  description = "Marketplace image for Windows 11 Enterprise 24H2 (Gen2). Confirm SKU availability in your region/subscription."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-ent"
    version   = "latest"
  }
}

variable "license_type" {
  description = "Windows license type for client images. Use Windows_Client when eligible for multitenant hosting rights."
  type        = string
  default     = "Windows_Client"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB. 256+ recommended when install_ollama pulls local models."
  type        = number
  default     = 256
}

variable "install_ollama" {
  description = "Install Ollama and configure OpenClaw to use a local model (no cloud LLM API key required)."
  type        = bool
  default     = true
}

variable "ollama_model" {
  description = "Ollama model tag to pull in a background task after bootstrap (e.g. llama3.2:3b, llama3.2)."
  type        = string
  default     = "llama3.2:3b"
}

variable "allowed_rdp_cidr" {
  description = "CIDR allowed to connect to the VM over RDP (3389)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "openclaw_gateway_port" {
  description = "TCP port exposed for the OpenClaw gateway."
  type        = number
  default     = 18789
}

variable "allowed_gateway_cidr" {
  description = "CIDR allowed to reach the OpenClaw gateway port."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_public_ip" {
  description = "Attach a static public IP for RDP and gateway access."
  type        = bool
  default     = true
}

variable "run_bootstrap_extension" {
  description = "Run the Custom Script Extension to install Node, WSL2, MXC SDK, and OpenClaw."
  type        = bool
  default     = true
}

variable "mxc_git_repo" {
  description = "Git URL for MXC source (ai-engineering-lab/ms-mxc fork). See dependencies.lock.json."
  type        = string
  default     = "https://github.com/ai-engineering-lab/ms-mxc.git"
}

variable "mxc_git_ref" {
  description = "Git branch, tag, or commit SHA for MXC source. See dependencies.lock.json."
  type        = string
  default     = "c1027bc5d750d161e81eb2b6a236d5772af5a3ac"
}

variable "openclaw_npm_package" {
  description = "Pinned npm package spec for OpenClaw (e.g. openclaw@2026.6.1). See dependencies.lock.json."
  type        = string
  default     = "openclaw@2026.6.1"
}

variable "openclaw_version" {
  description = "OpenClaw npm version without the package prefix. Used for outputs; keep in sync with openclaw_npm_package."
  type        = string
  default     = "2026.6.1"
}

variable "node_version" {
  description = "Pinned Node.js semver (e.g. 24.10.0). See dependencies.lock.json."
  type        = string
  default     = "24.10.0"
}

variable "ollama_version" {
  description = "Pinned Ollama release version without a leading v (e.g. 0.30.5). See dependencies.lock.json."
  type        = string
  default     = "0.30.5"
}

variable "git_for_windows_version" {
  description = "Pinned Git for Windows release tag suffix (e.g. 2.49.0.windows.1). See dependencies.lock.json."
  type        = string
  default     = "2.49.0.windows.1"
}

variable "openclaw_control_ui_disable_device_auth" {
  description = "Set gateway.controlUi.dangerouslyDisableDeviceAuth so Control UI works over plain HTTP from a remote browser. Lab/sandbox only."
  type        = bool
  default     = true
}

