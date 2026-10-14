output "portal_url" {
  description = "Customer portal (regional entry: Application Gateway WAF or Load Balancer)."
  value       = "http://${module.compute.public_fqdn}"
}

output "front_door_url" {
  description = "Global Front Door URL (when enabled)."
  value       = var.enable_front_door ? module.edge[0].endpoint_url : null
}

output "resource_groups" {
  description = "Resource groups created."
  value = {
    azure  = azurerm_resource_group.azure.name
    onprem = azurerm_resource_group.onprem.name
  }
}

output "key_vault_name" {
  description = "Key Vault holding the SSH key, SQL password and CMK."
  value       = module.security.key_vault_name
}

output "sql_server_fqdn" {
  description = "Azure SQL server (private endpoint only)."
  value       = module.data.sql_server_fqdn
}

output "storage_account_name" {
  description = "Blob storage account (private endpoint only)."
  value       = module.data.storage_account_name
}

output "connectivity_mode" {
  description = "peering or vpn."
  value       = module.connectivity.mode
}

output "vpn_gateway_public_ips" {
  description = "VPN gateway public IPs (vpn mode)."
  value       = module.connectivity.vpn_gateway_public_ips
}

output "onprem_test_vms" {
  description = "Private IPs of the simulated on-prem test machines."
  value       = module.onprem.test_vm_ips
}

output "backup_vault" {
  description = "Recovery Services vault protecting the fraud-detection VM."
  value       = module.backup.vault_name
}

output "aks_cluster_name" {
  description = "AKS cluster (when enable_aks)."
  value       = var.enable_aks ? module.aks[0].cluster_name : null
}

output "aks_get_credentials" {
  description = "Command to fetch kubeconfig (Entra ID auth; run kubelogin convert-kubeconfig -l azurecli afterwards)."
  value       = var.enable_aks ? "az aks get-credentials -g ${azurerm_resource_group.azure.name} -n ${module.aks[0].cluster_name}" : null
}
