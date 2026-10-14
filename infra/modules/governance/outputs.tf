output "custom_policy_definition_ids" {
  value = {
    require_tag        = azurerm_policy_definition.require_tag.id
    deny_nic_public_ip = azurerm_policy_definition.deny_nic_public_ip.id
    deny_public_data   = azurerm_policy_definition.deny_public_data.id
  }
  description = "IDs of the custom policy definitions."
}
