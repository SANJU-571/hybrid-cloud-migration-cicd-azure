# Policy-as-code guardrails (Azure Policy is free).
#
# Custom definitions live in ./policies/*.json and are versioned with the
# infrastructure. They are created at subscription scope and assigned to this
# project's resource groups only, so nothing else in the subscription is
# affected.
#
#   nfb-require-tag             every resource carries cost/ownership tags
#   nfb-deny-nic-public-ip      no VM network interface gets a public IP
#   nfb-deny-public-data        SQL and Storage must disable public network access
#   Allowed locations (built-in) Canada Central / Canada East only (data residency)

locals {
  effect_parameter = {
    effect = {
      type          = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      metadata      = { displayName = "Effect" }
    }
  }

  # Every (resource group, tag) pair gets its own assignment.
  tag_assignments = {
    for pair in setproduct(keys(var.resource_group_ids), var.required_tags) :
    "${pair[0]}-${pair[1]}" => { rg = pair[0], tag = pair[1] }
  }
}

resource "azurerm_policy_definition" "require_tag" {
  name         = "${var.name}-require-tag"
  display_name = "NFB: resources must have a '<tagName>' tag"
  description  = "Audits or denies resources that are missing the given tag. Used for cost allocation (FinOps) and ownership."
  policy_type  = "Custom"
  mode         = "Indexed"
  metadata     = jsonencode({ category = "Tags", version = "1.0.0" })
  policy_rule  = file("${path.module}/policies/require-tag.json")
  parameters = jsonencode(merge(local.effect_parameter, {
    tagName = {
      type     = "String"
      metadata = { displayName = "Tag name" }
    }
  }))
}

resource "azurerm_policy_definition" "deny_nic_public_ip" {
  name         = "${var.name}-deny-nic-public-ip"
  display_name = "NFB: network interfaces must not have public IPs"
  description  = "Servers are reached only through the WAF / load balancer or the private network."
  policy_type  = "Custom"
  mode         = "Indexed"
  metadata     = jsonencode({ category = "Network", version = "1.0.0" })
  policy_rule  = file("${path.module}/policies/deny-nic-public-ip.json")
  parameters   = jsonencode(local.effect_parameter)
}

resource "azurerm_policy_definition" "deny_public_data" {
  name         = "${var.name}-deny-public-data"
  display_name = "NFB: SQL servers and storage accounts must disable public network access"
  description  = "Data services are reachable only through private endpoints (PCI DSS segmentation, PIPEDA safeguards)."
  policy_type  = "Custom"
  mode         = "Indexed"
  metadata     = jsonencode({ category = "Network", version = "1.0.0" })
  policy_rule  = file("${path.module}/policies/deny-public-data-endpoints.json")
  parameters   = jsonencode(local.effect_parameter)
}

data "azurerm_policy_definition" "allowed_locations" {
  name = "e56962a6-4747-49cd-b67b-bf8b01975c4c" # built-in: Allowed locations
}

############################################
# Assignments (resource-group scope)
############################################
resource "azurerm_resource_group_policy_assignment" "require_tag" {
  for_each             = local.tag_assignments
  name                 = "require-tag-${each.value.tag}"
  display_name         = "Require tag '${each.value.tag}'"
  resource_group_id    = var.resource_group_ids[each.value.rg]
  policy_definition_id = azurerm_policy_definition.require_tag.id
  parameters = jsonencode({
    tagName = { value = each.value.tag }
    effect  = { value = var.tag_policy_effect }
  })
  non_compliance_message {
    content = "Add the '${each.value.tag}' tag (used for cost allocation and ownership)."
  }
}

resource "azurerm_resource_group_policy_assignment" "deny_nic_public_ip" {
  for_each             = var.resource_group_ids
  name                 = "deny-nic-public-ip"
  display_name         = "Deny public IPs on network interfaces"
  resource_group_id    = each.value
  policy_definition_id = azurerm_policy_definition.deny_nic_public_ip.id
  parameters           = jsonencode({ effect = { value = var.network_policy_effect } })
  non_compliance_message {
    content = "Servers must not have public IPs; publish through Application Gateway or a load balancer."
  }
}

resource "azurerm_resource_group_policy_assignment" "deny_public_data" {
  for_each             = var.resource_group_ids
  name                 = "deny-public-data"
  display_name         = "Deny public endpoints on SQL and Storage"
  resource_group_id    = each.value
  policy_definition_id = azurerm_policy_definition.deny_public_data.id
  parameters           = jsonencode({ effect = { value = var.network_policy_effect } })
  non_compliance_message {
    content = "Set publicNetworkAccess = Disabled and use a private endpoint."
  }
}

resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  for_each             = var.resource_group_ids
  name                 = "allowed-locations-canada"
  display_name         = "Allowed locations: Canada only"
  resource_group_id    = each.value
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id
  parameters           = jsonencode({ listOfAllowedLocations = { value = var.allowed_locations } })
  non_compliance_message {
    content = "Data residency: deploy only to ${join(", ", var.allowed_locations)}."
  }
}
