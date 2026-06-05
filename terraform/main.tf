resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  resource_suffix = random_string.suffix.result
  base_name       = "${var.name_prefix}-${local.resource_suffix}"
}

resource "azurerm_resource_group" "main" {
  name     = "${local.base_name}-rg"
  location = var.location
  tags     = var.tags
}
