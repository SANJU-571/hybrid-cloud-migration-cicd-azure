output "sql_server_fqdn" {
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
  description = "SQL server FQDN (resolves to a private IP inside the network)."
}

output "storage_account_name" {
  value       = azurerm_storage_account.this.name
  description = "Storage account name."
}
