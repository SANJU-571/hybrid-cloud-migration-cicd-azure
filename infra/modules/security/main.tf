# Identity, secrets and keys.
#   Microsoft Entra ID identities + Azure RBAC
#   Azure Key Vault secrets
#   Azure Key Vault Premium (HSM-backed keys)

############################################
# Workload identity (no credentials stored on VMs)
############################################
resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${var.name}-workload"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

############################################
# Key Vault
############################################
resource "azurerm_key_vault" "this" {
  name                          = substr("kv-${replace(var.name, "-", "")}-${var.suffix}", 0, 24)
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "premium" # HSM-backed keys
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = var.tags

  network_acls {
    # Lab trade-off: GitHub-hosted runners have no fixed IPs, so the data
    # plane stays reachable but every call still requires Entra ID + RBAC.
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

resource "azurerm_role_assignment" "deployer_kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.deployer_object_id
}

resource "azurerm_role_assignment" "workload_kv_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

# Azure RBAC can take a minute to propagate before data-plane calls succeed.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer_kv_admin]
  create_duration = "90s"
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "audit"
  }
}

############################################
# Generated credentials -> stored only in Key Vault
############################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_password" "sql_admin" {
  length           = 28
  special          = true
  override_special = "!#%*-_+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Secrets expire after one year; rotate by re-running Terraform (taint/replace).
resource "time_offset" "secret_expiry" {
  offset_years = 1
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  name            = "vm-ssh-private-key"
  value           = tls_private_key.ssh.private_key_openssh
  key_vault_id    = azurerm_key_vault.this.id
  content_type    = "text/plain; openssh-private-key"
  expiration_date = time_offset.secret_expiry.rfc3339
  tags            = var.tags
  depends_on      = [time_sleep.rbac_propagation]
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name            = "sql-admin-password"
  value           = random_password.sql_admin.result
  key_vault_id    = azurerm_key_vault.this.id
  content_type    = "password"
  expiration_date = time_offset.secret_expiry.rfc3339
  tags            = var.tags
  depends_on      = [time_sleep.rbac_propagation]
}

############################################
# Customer-managed encryption key (HSM) with automatic rotation
############################################
resource "azurerm_key_vault_key" "cmk" {
  name         = "cmk-data"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA-HSM"
  key_size     = 3072
  key_opts     = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
  tags         = var.tags

  rotation_policy {
    expire_after         = "P1Y"
    notify_before_expiry = "P30D"

    automatic {
      time_before_expiry = "P60D"
    }
  }

  depends_on = [time_sleep.rbac_propagation]
}

############################################
# Microsoft Defender for Cloud (optional, subscription-wide)
############################################
locals {
  defender_plans = var.enable_defender_for_cloud ? {
    VirtualMachines = "P1"
    SqlServers      = null
    StorageAccounts = "DefenderForStorageV2"
    KeyVaults       = null
  } : {}
}

resource "azurerm_security_center_subscription_pricing" "this" {
  for_each      = local.defender_plans
  tier          = "Standard"
  resource_type = each.key
  subplan       = each.value
}
