variable "name" {
  type        = string
  description = "Name prefix (keeps policy names unique per environment)."
}

variable "resource_group_ids" {
  type        = map(string)
  description = "Resource groups the guardrails are assigned to, keyed by a short name."
}

variable "allowed_locations" {
  type        = list(string)
  description = "Regions resources may be created in (Canadian data residency)."
}

variable "required_tags" {
  type        = list(string)
  description = "Tags every resource must carry (cost allocation and ownership)."
}

variable "tag_policy_effect" {
  type        = string
  description = "Effect for missing tags: Audit (report) or Deny (block)."
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.tag_policy_effect)
    error_message = "tag_policy_effect must be Audit, Deny or Disabled."
  }
}

variable "network_policy_effect" {
  type        = string
  description = "Effect for public IPs on NICs and public SQL/Storage endpoints."
  default     = "Deny"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.network_policy_effect)
    error_message = "network_policy_effect must be Audit, Deny or Disabled."
  }
}
