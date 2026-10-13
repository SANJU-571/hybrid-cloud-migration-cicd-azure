# Observability, audit and cost governance.
#   Azure Monitor + Log Analytics + metric alerts
#   Azure Activity Log exported to Log Analytics
#   Microsoft Cost Management budget

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 90 # audit evidence kept 90 days
  daily_quota_gb      = 1  # hard cap so a lab can never run up a log bill
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-${var.name}-ops"
  resource_group_name = var.resource_group_name
  short_name          = "nfbops"
  tags                = var.tags

  email_receiver {
    name                    = "ops-team"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Subscription Activity Log -> Log Analytics (control-plane audit trail)
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-${var.name}-activity-log"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = ["Administrative", "Security", "Policy", "Alert", "ServiceHealth"]
    content {
      category = enabled_log.value
    }
  }
}

# Security alert: any change to firewall (NSG) rules is emailed immediately
resource "azurerm_monitor_activity_log_alert" "nsg_change" {
  name                = "alert-${var.name}-nsg-rule-change"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = ["/subscriptions/${var.subscription_id}"]
  description         = "A Network Security Group rule was created, changed or deleted."
  tags                = var.tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Network/networkSecurityGroups/securityRules/write"
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

# Cost governance: monthly budget with email alerts.
# time_static records the creation time once, so the budget start date is
# stable across runs (and unknown, not empty, during `terraform validate`).
resource "time_static" "budget_start" {}

resource "azurerm_consumption_budget_resource_group" "this" {
  name              = "budget-${var.name}"
  resource_group_id = var.resource_group_id
  amount            = var.monthly_budget_usd
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", time_static.budget_start.rfc3339)
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = notification.value == 100 ? "Forecasted" : "Actual"
      contact_emails = [var.alert_email]
    }
  }

}
