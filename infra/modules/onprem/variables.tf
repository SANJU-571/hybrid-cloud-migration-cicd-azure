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
  description = "Resource group for the on-prem simulation."
}

variable "vnet_cidr" {
  type        = string
  description = "On-prem address space."
}

variable "subnets" {
  type        = map(string)
  description = "Must contain GatewaySubnet, managers, employees, core_banking, onprem_db."
}

variable "azure_vnet_cidr" {
  type        = string
  description = "Azure VNet range (Employees are blocked from it)."
}

variable "deploy_test_vms" {
  type        = bool
  description = "Deploy Manager PC, Employee PC and on-prem DB VMs for ACL validation."
}

variable "vm_size" {
  type        = string
  description = "VM size for test VMs."
}

variable "admin_username" {
  type        = string
  description = "Admin username."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
