variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ca-central-1"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "openclaw-linux"
}

variable "instance_type" {
  description = "EC2 instance type. c6i.2xlarge (8 vCPU, 16 GB) recommended for llama3.2:1b on CPU."
  type        = string
  default     = "c6i.2xlarge"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB (Ollama models need space)."
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size_gb >= 40 && var.root_volume_size_gb <= 500
    error_message = "root_volume_size_gb must be between 40 and 500."
  }
}

variable "ec2_key_name" {
  description = "Existing EC2 key pair name in the target region (required for SSH)."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to SSH into the instance."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_gateway_cidr" {
  description = "CIDR blocks allowed to reach the OpenClaw gateway port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "openclaw_gateway_port" {
  description = "TCP port exposed for the OpenClaw gateway Control UI."
  type        = number
  default     = 18789
}

variable "install_ollama" {
  description = "Install Ollama and configure OpenClaw to use a local model."
  type        = bool
  default     = true
}

variable "ollama_model" {
  description = "Ollama model tag to pull after bootstrap."
  type        = string
  default     = "llama3.2:1b"
}

variable "openclaw_npm_package" {
  description = "Pinned npm package spec for OpenClaw. See dependencies.lock.json."
  type        = string
  default     = "openclaw@2026.6.1"
}

variable "openclaw_version" {
  description = "OpenClaw npm version without package prefix (for outputs)."
  type        = string
  default     = "2026.6.1"
}

variable "node_version" {
  description = "Pinned Node.js semver. See dependencies.lock.json."
  type        = string
  default     = "24.10.0"
}

variable "ollama_version" {
  description = "Pinned Ollama release without leading v. See dependencies.lock.json."
  type        = string
  default     = "0.30.5"
}

variable "openclaw_control_ui_disable_device_auth" {
  description = "Disable Control UI device auth for plain HTTP lab access. Sandbox only."
  type        = bool
  default     = true
}

variable "mxc_sdk_version" {
  description = "Pinned npm version for @microsoft/mxc-sdk. See dependencies.lock.json."
  type        = string
  default     = "0.6.1"
}

variable "mxc_backend" {
  description = "MXC containment backend on Linux: bubblewrap (default) or lxc."
  type        = string
  default     = "bubblewrap"

  validation {
    condition     = contains(["bubblewrap", "lxc"], var.mxc_backend)
    error_message = "mxc_backend must be bubblewrap or lxc."
  }
}

variable "install_mxc" {
  description = "Install MXC runtime, SDK, and sandbox profiles during bootstrap."
  type        = bool
  default     = true
}

variable "owner_tag" {
  description = "Owner tag applied to AWS resources."
  type        = string
  default     = "ai-engineering-lab"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 7
}
