variable "name" {
  type        = string
  description = "Name prefix."
}

variable "suffix" {
  type        = string
  description = "Random suffix for the public DNS label."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones."
}

variable "web_subnet_id" {
  type        = string
  description = "Web tier subnet."
}

variable "app_subnet_id" {
  type        = string
  description = "Private app tier subnet."
}

variable "appgw_subnet_id" {
  type        = string
  description = "Dedicated Application Gateway subnet."
}

variable "fraud_detection_ip" {
  type        = string
  description = "Static private IP of the fraud-detection VM."
}

variable "enable_app_gateway_waf" {
  type        = bool
  description = "Use Application Gateway WAF_v2 (true) or a public Standard Load Balancer (false)."
}

variable "web_vm_size" {
  type        = string
  description = "Web tier VM size."
}

variable "app_vm_size" {
  type        = string
  description = "App tier VM size."
}

variable "web_instance_min" {
  type        = number
  description = "Autoscale minimum."
}

variable "web_instance_max" {
  type        = number
  description = "Autoscale maximum."
}

variable "admin_username" {
  type        = string
  description = "Admin username."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key."
}

variable "workload_identity_id" {
  type        = string
  description = "User-assigned identity attached to VMs."
}

variable "key_vault_uri" {
  type        = string
  description = "Key Vault URI (exposed to workloads as a tag for discovery)."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace."
}

variable "action_group_id" {
  type        = string
  description = "Action group for alerts."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
