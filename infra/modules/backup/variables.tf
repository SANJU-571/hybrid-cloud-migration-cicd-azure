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
  description = "Resource group."
}

variable "geo_redundant" {
  type        = bool
  description = "Geo-redundant vault storage with cross-region restore."
}

variable "protected_vm_ids" {
  type        = map(string)
  description = "VMs to protect, keyed by a static name."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
