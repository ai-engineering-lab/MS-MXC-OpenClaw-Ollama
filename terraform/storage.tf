resource "azurerm_storage_account" "bootstrap" {
  count = var.run_bootstrap_extension ? 1 : 0

  name                     = replace("${var.name_prefix}${local.resource_suffix}sa", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_container" "scripts" {
  count = var.run_bootstrap_extension ? 1 : 0

  name                  = "scripts"
  storage_account_id    = azurerm_storage_account.bootstrap[0].id
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "bootstrap" {
  count = var.run_bootstrap_extension ? 1 : 0

  name                   = "bootstrap.ps1"
  storage_account_name   = azurerm_storage_account.bootstrap[0].name
  storage_container_name = azurerm_storage_container.scripts[0].name
  type                   = "Block"
  content_type           = "text/plain"

  source = "${path.module}/../scripts/bootstrap.ps1"
}
