# Backup & disaster recovery.
#   Recovery Services vault + daily backup policy (Azure Backup)

resource "azurerm_recovery_services_vault" "this" {
  name                         = "rsv-${var.name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "Standard"
  storage_mode_type            = var.geo_redundant ? "GeoRedundant" : "LocallyRedundant"
  cross_region_restore_enabled = var.geo_redundant
  tags                         = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_backup_policy_vm" "daily" {
  name                = "bkpol-${var.name}-daily"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  timezone            = "Eastern Standard Time"

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 7
  }

  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

resource "azurerm_backup_protected_vm" "this" {
  for_each            = var.protected_vm_ids
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  source_vm_id        = each.value
  backup_policy_id    = azurerm_backup_policy_vm.daily.id
}
