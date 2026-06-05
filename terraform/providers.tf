provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = false
    }
  }

  # Omit subscription_id to use the Azure CLI default subscription.
  subscription_id = var.subscription_id != null ? var.subscription_id : null
}
