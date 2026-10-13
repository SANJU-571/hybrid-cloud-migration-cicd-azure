# Data tier.
#   Azure SQL Database (private endpoint only)
#   Azure Blob Storage (versioning, GRS, lifecycle, CMK encryption)

locals {
  compact = replace(var.name, "-", "")
}

############################################
# Private DNS so names resolve to private IPs from Azure AND on-prem
############################################
locals {
  dns_zones = {
    sql  = "privatelink.database.windows.net"
    blob = "privatelink.blob.core.windows.net"
  }
  dns_links = {
    for pair in setproduct(keys(local.dns_zones), keys(var.dns_link_vnet_ids)) :
    "${pair[0]}-${pair[1]}" => { zone = pair[0], vnet = pair[1] }
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.dns_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = local.dns_links
  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone].name
  virtual_network_id    = var.dns_link_vnet_ids[each.value.vnet]
  tags                  = var.tags
}

############################################
# Azure SQL Database
############################################
resource "azurerm_mssql_server" "this" {
  name                          = "sql-${var.name}-${var.suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  version                       = "12.0"
  administrator_login           = "sqladminuser"
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = var.tags

  # Entra ID (Azure AD) authentication alongside the break-glass SQL login
  azuread_administrator {
    login_username = "sql-entra-admin"
    object_id      = var.sql_entra_admin_object_id
  }
}

resource "azurerm_mssql_database" "core" {
  name           = "sqldb-core-banking"
  server_id      = azurerm_mssql_server.this.id
  sku_name       = var.sql_sku
  max_size_gb    = 2
  zone_redundant = false
  tags           = var.tags

  short_term_retention_policy {
    retention_days = 7
  }
}

resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  log_monitoring_enabled = true
  retention_in_days      = 90
}

resource "azurerm_monitor_diagnostic_setting" "sql_audit" {
  name                       = "diag-audit-to-law"
  target_resource_id         = "${azurerm_mssql_server.this.id}/databases/master"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }

  depends_on = [azurerm_mssql_server_extended_auditing_policy.this]
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${var.name}-sql"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "sql"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["sql"].id]
  }
}

############################################
# Blob Storage (documents, statements, backups)
############################################
resource "azurerm_user_assigned_identity" "storage" {
  name                = "id-${var.name}-storage-cmk"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "storage_cmk" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.storage.principal_id
}

resource "time_sleep" "cmk_rbac" {
  depends_on      = [azurerm_role_assignment.storage_cmk]
  create_duration = "60s"
}

resource "azurerm_storage_account" "this" {
  name                              = substr("st${local.compact}${var.suffix}", 0, 24)
  location                          = var.location
  resource_group_name               = var.resource_group_name
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = var.storage_replication
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = false
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.storage.id]
  }

  customer_managed_key {
    key_vault_key_id          = var.cmk_versionless_id
    user_assigned_identity_id = azurerm_user_assigned_identity.storage.id
  }

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  depends_on = [time_sleep.cmk_rbac]
}

# Blob read/write/delete access logs -> Log Analytics
resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "diag-blob-to-law"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_storage_container" "this" {
  for_each              = toset(["statements", "documents", "app-assets"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Lifecycle management: tier cold data to Cool/Archive for cost control
resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "tier-and-expire"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 180
        delete_after_days_since_modification_greater_than          = 2555 # ~7 years (financial record retention)
      }
      version {
        delete_after_days_since_creation = 90
      }
    }
  }
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["blob"].id]
  }
}
