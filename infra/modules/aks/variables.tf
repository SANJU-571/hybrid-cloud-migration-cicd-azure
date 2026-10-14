variable "name" {
  type        = string
  description = "Name prefix."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the cluster."
}

variable "tenant_id" {
  type        = string
  description = "Entra ID tenant used for Kubernetes RBAC."
}

variable "subnet_id" {
  type        = string
  description = "Subnet for the node pool and internal load balancers (snet-aks, NAT Gateway attached)."
}

variable "availability_zones" {
  type        = list(string)
  description = "Zones for the node pool."
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version; null = AKS default. Patch upgrades are automatic."
  default     = null
}

variable "node_vm_size" {
  type        = string
  description = "Node VM size."
  default     = "Standard_B2s"
}

variable "node_min_count" {
  type        = number
  description = "Cluster autoscaler minimum nodes."
  default     = 1
}

variable "node_max_count" {
  type        = number
  description = "Cluster autoscaler maximum nodes."
  default     = 2
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Workspace for Container Insights and control-plane audit logs."
}

variable "admin_object_ids" {
  type        = list(string)
  description = "Entra ID object IDs granted Azure Kubernetes Service RBAC Cluster Admin."
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "Optional CIDRs allowed to reach the API server. Empty = any (Entra ID auth still required)."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags."
}
