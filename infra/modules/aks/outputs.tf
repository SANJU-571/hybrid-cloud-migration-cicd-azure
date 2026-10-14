output "cluster_name" {
  value       = azurerm_kubernetes_cluster.this.name
  description = "AKS cluster name."
}

output "cluster_id" {
  value       = azurerm_kubernetes_cluster.this.id
  description = "AKS cluster resource ID."
}

output "oidc_issuer_url" {
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
  description = "OIDC issuer for workload identity federation."
}

output "node_resource_group" {
  value       = azurerm_kubernetes_cluster.this.node_resource_group
  description = "Resource group AKS manages for nodes and load balancers."
}
