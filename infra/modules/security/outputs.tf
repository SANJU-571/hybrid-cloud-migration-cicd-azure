output "key_vault_id" {
  value       = azurerm_key_vault.this.id
  description = "Key Vault ID."
}

output "key_vault_name" {
  value       = azurerm_key_vault.this.name
  description = "Key Vault name."
}

output "key_vault_uri" {
  value       = azurerm_key_vault.this.vault_uri
  description = "Key Vault URI."
}

output "cmk_versionless_id" {
  value       = azurerm_key_vault_key.cmk.versionless_id
  description = "Versionless ID of the customer-managed key (auto-rotation friendly)."
}

output "workload_identity_id" {
  value       = azurerm_user_assigned_identity.workload.id
  description = "User-assigned managed identity for workloads."
}

output "ssh_public_key" {
  value       = tls_private_key.ssh.public_key_openssh
  description = "Public half of the generated VM SSH key."
}

output "sql_admin_password" {
  value       = random_password.sql_admin.result
  sensitive   = true
  description = "Generated SQL admin password (also stored in Key Vault)."
}
