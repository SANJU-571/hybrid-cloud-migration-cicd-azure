output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.this.id
  description = "Log Analytics workspace ID."
}

output "action_group_id" {
  value       = azurerm_monitor_action_group.ops.id
  description = "Ops action group ID."
}
