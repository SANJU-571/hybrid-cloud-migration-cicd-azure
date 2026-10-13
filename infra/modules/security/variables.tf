variable "name" {
  type        = string
  description = "Name prefix."
}

variable "suffix" {
  type        = string
  description = "Random suffix for globally unique names."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group."
}

variable "tenant_id" {
  type        = string
  description = "Entra ID tenant."
}

variable "deployer_object_id" {
  type        = string
  description = "Object ID of the identity running Terraform."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Workspace for Key Vault audit logs."
}

variable "enable_defender_for_cloud" {
  type        = bool
  description = "Enable Defender for Cloud plans on the subscription."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
