############################################
# General
############################################
variable "project" {
  description = "Short project code used in resource names."
  type        = string
  default     = "nfb"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.project))
    error_message = "project must be 2-6 lowercase letters/digits (it is used in globally unique names)."
  }
}

variable "environment" {
  description = "Environment name (lab, full, prod...)."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "canadacentral"
}

variable "availability_zones" {
  description = "Zones used by the web tier and Application Gateway. Use [] for regions without zone support."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "cost_center" {
  description = "Cost-allocation tag applied to every resource (FinOps reporting, required by policy)."
  type        = string
  default     = "nfb-cloud-lab"
}

variable "allowed_locations" {
  description = "Regions the governance policy allows (Canadian data residency). Must include var.location."
  type        = list(string)
  default     = ["canadacentral", "canadaeast"]
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

############################################
# Feature flags (cost control)
############################################
variable "connectivity_mode" {
  description = <<-EOT
    How the simulated on-premises network reaches Azure:
      "peering" - VNet peering (cheap, instant) - default for the lab
      "vpn"     - two VpnGw1AZ gateways + IPsec Site-to-Site tunnel (~US$0.40/hr, 30-45 min to provision)
  EOT
  type        = string
  default     = "peering"

  validation {
    condition     = contains(["peering", "vpn"], var.connectivity_mode)
    error_message = "connectivity_mode must be \"peering\" or \"vpn\"."
  }
}

variable "enable_app_gateway_waf" {
  description = "Front the web tier with Application Gateway WAF_v2 (~US$0.45/hr). When false, a public Standard Load Balancer is used instead."
  type        = bool
  default     = true
}

variable "enable_front_door" {
  description = "Add Azure Front Door Standard as the global entry point / CDN (~US$35/month base)."
  type        = bool
  default     = false
}

variable "enable_ddos_protection" {
  description = "Attach an Azure DDoS Network Protection plan to the VNet (~US$2,950/month!). Keep false outside production."
  type        = bool
  default     = false
}

variable "enable_defender_for_cloud" {
  description = "Turn on Microsoft Defender for Cloud plans (VMs, SQL, Storage, Key Vault) for the whole subscription."
  type        = bool
  default     = false
}

variable "enable_aks" {
  description = "Deploy AKS (Free tier control plane + 1-2 Standard_B2s nodes, ~US$1.5-3/day) and run the fraud-detection API on it via Helm."
  type        = bool
  default     = false
}

variable "enable_governance" {
  description = "Create the Azure Policy guardrails (free). Needs Resource Policy Contributor for the deploying identity."
  type        = bool
  default     = true
}

variable "tag_policy_effect" {
  description = "Effect of the required-tags policy: Audit (report only) or Deny (block untagged resources)."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.tag_policy_effect)
    error_message = "tag_policy_effect must be Audit, Deny or Disabled."
  }
}

variable "deploy_onprem_test_vms" {
  description = "Deploy a Manager PC and an Employee PC in the simulated on-prem network to prove the ACL/NSG rules."
  type        = bool
  default     = true
}

############################################
# Compute
############################################
variable "web_vm_size" {
  description = "VM size for the customer-portal scale set."
  type        = string
  default     = "Standard_B1s"
}

variable "app_vm_size" {
  description = "VM size for the private fraud-detection service and on-prem test VMs."
  type        = string
  default     = "Standard_B1s"
}

variable "web_instance_min" {
  description = "Minimum instances in the web scale set."
  type        = number
  default     = 2
}

variable "web_instance_max" {
  description = "Maximum instances in the web scale set."
  type        = number
  default     = 4
}

variable "admin_username" {
  description = "Admin username for Linux VMs (SSH key auth only)."
  type        = string
  default     = "azureops"
}

############################################
# Data
############################################
variable "sql_sku" {
  description = "Azure SQL Database SKU. Basic is ~US$5/month."
  type        = string
  default     = "Basic"
}

variable "storage_replication" {
  description = "Storage replication type. GRS gives cross-region durability (deck: 'cross-region replication')."
  type        = string
  default     = "GRS"
}

############################################
# Operations
############################################
variable "alert_email" {
  description = "Email that receives monitoring alerts and budget notifications."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the resource group; alerts at 50/80/100%."
  type        = number
  default     = 150
}

variable "backup_geo_redundant" {
  description = "Use geo-redundant storage for the Recovery Services vault (enables cross-region restore)."
  type        = bool
  default     = false
}

############################################
# Addressing (kept identical to the Packet Tracer design)
############################################
variable "azure_vnet_cidr" {
  description = "Address space of the Azure VNet."
  type        = string
  default     = "192.168.200.0/21"
}

variable "onprem_vnet_cidr" {
  description = "Address space of the simulated on-premises network."
  type        = string
  default     = "192.168.0.0/17"
}

############################################
# AKS (only used when enable_aks = true)
############################################
variable "aks_kubernetes_version" {
  description = "AKS Kubernetes version; null = current AKS default (patches are applied automatically)."
  type        = string
  default     = null
}

variable "aks_node_vm_size" {
  description = "AKS node size."
  type        = string
  default     = "Standard_B2s"
}

variable "aks_node_max_count" {
  description = "Cluster autoscaler maximum node count."
  type        = number
  default     = 2
}

variable "aks_admin_object_ids" {
  description = "Extra Entra ID object IDs (e.g. your user) granted AKS RBAC Cluster Admin. The deploying identity is always included."
  type        = list(string)
  default     = []
}

variable "aks_api_authorized_ip_ranges" {
  description = "Optional CIDRs allowed to reach the AKS API server. Empty = any source (Entra ID auth still required)."
  type        = list(string)
  default     = []
}
