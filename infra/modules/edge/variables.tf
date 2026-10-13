variable "name" {
  type        = string
  description = "Name prefix."
}

variable "suffix" {
  type        = string
  description = "Random suffix."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group."
}

variable "origin_host" {
  type        = string
  description = "FQDN of the regional entry point (Application Gateway / Load Balancer)."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
