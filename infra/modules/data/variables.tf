variable "name" {
  type        = string
  description = "Name prefix."
}

variable "suffix" {
  type        = string
  description = "Random suffix for globally unique names."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group."
}

variable "data_subnet_id" {
  type        = string
  description = "Subnet for private endpoints."
}

variable "dns_link_vnet_ids" {
  type        = map(string)
  description = "VNets that must resolve the private endpoints (Azure + on-prem)."
}

variable "sql_entra_admin_object_id" {
  type        = string
  description = "Object ID of the Entra ID principal set as SQL administrator."
}

variable "sql_sku" {
  type        = string
  description = "Azure SQL Database SKU."
}

variable "sql_admin_password" {
  type        = string
  sensitive   = true
  description = "SQL admin password (generated, stored in Key Vault)."
}

variable "key_vault_id" {
  type        = string
  description = "Key Vault holding the customer-managed key."
}

variable "cmk_versionless_id" {
  type        = string
  description = "Versionless customer-managed key ID."
}

variable "storage_replication" {
  type        = string
  description = "Storage replication (LRS, ZRS, GRS, GZRS...)."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Workspace for SQL auditing."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
