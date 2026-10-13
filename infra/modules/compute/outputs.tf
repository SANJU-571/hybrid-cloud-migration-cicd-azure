output "public_ip_address" {
  value       = azurerm_public_ip.ingress.ip_address
  description = "Public IP of the customer portal."
}

output "public_fqdn" {
  value       = azurerm_public_ip.ingress.fqdn
  description = "Public DNS name of the customer portal."
}

output "vmss_id" {
  value       = azurerm_linux_virtual_machine_scale_set.web.id
  description = "Web VM Scale Set ID."
}

output "fraud_detection_vm_id" {
  value       = azurerm_linux_virtual_machine.fraud.id
  description = "Fraud-detection VM ID (protected by Azure Backup)."
}

output "app_gateway_id" {
  value       = local.use_agw ? azurerm_application_gateway.this[0].id : null
  description = "Application Gateway ID, if enabled."
}
