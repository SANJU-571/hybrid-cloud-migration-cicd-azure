output "endpoint_url" {
  value       = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}"
  description = "Front Door URL."
}
