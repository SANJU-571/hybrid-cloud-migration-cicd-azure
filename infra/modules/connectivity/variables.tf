variable "name" {
  type        = string
  description = "Name prefix."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "mode" {
  type        = string
  description = "\"vpn\" or \"peering\"."
}

variable "azure_resource_group_name" {
  type        = string
  description = "Azure-side resource group."
}

variable "onprem_resource_group_name" {
  type        = string
  description = "On-prem-side resource group."
}

variable "azure_vnet_id" {
  type        = string
  description = "Azure VNet ID."
}

variable "azure_vnet_name" {
  type        = string
  description = "Azure VNet name."
}

variable "azure_vnet_cidr" {
  type        = string
  description = "Azure address space."
}

variable "azure_gateway_subnet_id" {
  type        = string
  description = "Azure GatewaySubnet ID."
}

variable "onprem_vnet_id" {
  type        = string
  description = "On-prem VNet ID."
}

variable "onprem_vnet_name" {
  type        = string
  description = "On-prem VNet name."
}

variable "onprem_vnet_cidr" {
  type        = string
  description = "On-prem address space."
}

variable "onprem_gateway_subnet_id" {
  type        = string
  description = "On-prem GatewaySubnet ID."
}

variable "availability_zones" {
  type        = list(string)
  description = "Zones for the gateway public IPs (empty = non-zonal region)."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
