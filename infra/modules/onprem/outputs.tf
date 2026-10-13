output "vnet_id" {
  value       = azurerm_virtual_network.this.id
  description = "On-prem VNet ID."
}

output "vnet_name" {
  value       = azurerm_virtual_network.this.name
  description = "On-prem VNet name."
}

output "gateway_subnet_id" {
  value       = azurerm_subnet.this["GatewaySubnet"].id
  description = "GatewaySubnet ID for the simulated on-prem VPN device."
}

output "test_vm_ips" {
  value       = { for k, v in local.test_vms : k => v.ip }
  description = "Private IPs of the test VMs."
}
