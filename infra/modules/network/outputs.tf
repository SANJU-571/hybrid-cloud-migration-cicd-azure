output "vnet_id" {
  value       = azurerm_virtual_network.this.id
  description = "Azure VNet ID."
}

output "vnet_name" {
  value       = azurerm_virtual_network.this.name
  description = "Azure VNet name."
}

output "subnet_ids" {
  value       = { for k, s in azurerm_subnet.this : k => s.id }
  description = "Subnet IDs keyed by logical name."
}
