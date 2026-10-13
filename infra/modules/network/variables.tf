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
  description = "Resource group for networking resources."
}

variable "vnet_cidr" {
  type        = string
  description = "VNet address space."
}

variable "subnets" {
  type        = map(string)
  description = "Subnet name => CIDR. Must contain GatewaySubnet, AppGatewaySubnet, web, data, app."
}

variable "managers_cidr" {
  type        = string
  description = "On-prem Manager VLAN (VLAN 30)."
}

variable "employees_cidr" {
  type        = string
  description = "On-prem Employee VLAN (VLAN 40)."
}

variable "public_ingress_via_lb" {
  type        = bool
  description = "True when the web tier is exposed directly through a public Load Balancer instead of Application Gateway."
}

variable "enable_ddos_protection" {
  type        = bool
  description = "Create and attach a DDoS Network Protection plan."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
