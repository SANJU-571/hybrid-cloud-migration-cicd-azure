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

variable "resource_group_id" {
  type        = string
  description = "Resource group ID (budget scope)."
}

variable "subscription_id" {
  type        = string
  description = "Subscription ID (Activity Log export)."
}

variable "alert_email" {
  type        = string
  description = "Alert recipient."
}

variable "monthly_budget_usd" {
  type        = number
  description = "Monthly budget amount."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
}
