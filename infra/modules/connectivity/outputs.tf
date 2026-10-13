output "mode" {
  value       = var.mode
  description = "Connectivity mode in use."
}

output "vpn_gateway_public_ips" {
  value       = { for k, p in azurerm_public_ip.gw : k => p.ip_address }
  description = "Public IPs of the VPN gateways (vpn mode only)."
}
