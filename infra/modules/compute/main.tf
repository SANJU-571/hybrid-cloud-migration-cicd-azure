# Compute tier.
#   Linux VM Scale Set + Azure Autoscale      - customer-portal microservice
#   Application Gateway WAF_v2                - L7 load balancing + OWASP protection
#   Azure Load Balancer (Standard)            - used instead when the WAF is disabled
#   VMSS rolling upgrades + Application Health extension - zero-downtime releases

locals {
  zones   = length(var.availability_zones) > 0 ? var.availability_zones : null
  use_agw = var.enable_app_gateway_waf
  image = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

############################################
# Public entry point
############################################
resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.name}-ingress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zones
  domain_name_label   = "${var.name}-portal-${var.suffix}"
  tags                = var.tags
}

############################################
# Option A: Application Gateway WAF_v2 (OWASP rules, Prevention mode)
############################################
resource "azurerm_web_application_firewall_policy" "this" {
  count               = local.use_agw ? 1 : 0
  name                = "waf-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}

resource "azurerm_application_gateway" "this" {
  count               = local.use_agw ? 1 : 0
  name                = "agw-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  zones               = local.zones
  firewall_policy_id  = azurerm_web_application_firewall_policy.this[0].id
  tags                = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  gateway_ip_configuration {
    name      = "gwip"
    subnet_id = var.appgw_subnet_id
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.ingress.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  backend_address_pool {
    name = "web-vmss"
  }

  probe {
    name                                      = "health"
    protocol                                  = "Http"
    path                                      = "/health"
    interval                                  = 15
    timeout                                   = 10
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  backend_http_settings {
    name                                = "web-http"
    protocol                            = "Http"
    port                                = 80
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    probe_name                          = "health"
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = "http"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "portal"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "http"
    backend_address_pool_name  = "web-vmss"
    backend_http_settings_name = "web-http"
  }
}

############################################
# Option B: public Standard Load Balancer (no WAF, lower cost)
############################################
resource "azurerm_lb" "web" {
  count               = local.use_agw ? 0 : 1
  name                = "lb-${var.name}-web"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.ingress.id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  count           = local.use_agw ? 0 : 1
  name            = "web-vmss"
  loadbalancer_id = azurerm_lb.web[0].id
}

resource "azurerm_lb_probe" "web" {
  count           = local.use_agw ? 0 : 1
  name            = "health"
  loadbalancer_id = azurerm_lb.web[0].id
  protocol        = "Http"
  port            = 80
  request_path    = "/health"
}

resource "azurerm_lb_rule" "http" {
  count                          = local.use_agw ? 0 : 1
  name                           = "http"
  loadbalancer_id                = azurerm_lb.web[0].id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web[0].id]
  probe_id                       = azurerm_lb_probe.web[0].id
  disable_outbound_snat          = true # outbound goes through the NAT Gateway
}

############################################
# Web tier: VM Scale Set (customer portal microservice)
############################################
resource "azurerm_linux_virtual_machine_scale_set" "web" {
  name                            = "vmss-${var.name}-web"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  sku                             = var.web_vm_size
  instances                       = var.web_instance_min
  zones                           = local.zones
  zone_balance                    = local.zones != null
  admin_username                  = var.admin_username
  disable_password_authentication = true
  upgrade_mode                    = "Rolling"
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  custom_data                     = base64encode(templatefile("${path.module}/cloud-init/web.yaml.tftpl", { fraud_detection_ip = var.fraud_detection_ip }))
  tags                            = merge(var.tags, { tier = "web", key_vault = var.key_vault_uri })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.workload_identity_id]
  }

  network_interface {
    name    = "nic-web"
    primary = true

    ip_configuration {
      name                                         = "ipconfig1"
      primary                                      = true
      subnet_id                                    = var.web_subnet_id
      application_gateway_backend_address_pool_ids = local.use_agw ? [for p in azurerm_application_gateway.this[0].backend_address_pool : p.id] : null
      load_balancer_backend_address_pool_ids       = local.use_agw ? null : [azurerm_lb_backend_address_pool.web[0].id]
    }
  }

  # Blue/green-style safety for every image or config change
  rolling_upgrade_policy {
    max_batch_instance_percent              = 50
    max_unhealthy_instance_percent          = 50
    max_unhealthy_upgraded_instance_percent = 50
    pause_time_between_batches              = "PT30S"
  }

  extension {
    name                       = "HealthExtension"
    publisher                  = "Microsoft.ManagedServices"
    type                       = "ApplicationHealthLinux"
    type_handler_version       = "1.0"
    auto_upgrade_minor_version = true
    settings = jsonencode({
      protocol    = "http"
      port        = 80
      requestPath = "/health"
    })
  }

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT30M"
  }

  boot_diagnostics {}

  lifecycle {
    # Autoscale owns the instance count after creation
    ignore_changes = [instances]
  }

  depends_on = [azurerm_lb_rule.http]
}

resource "azurerm_monitor_autoscale_setting" "web" {
  name                = "as-${var.name}-web"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.web.id
  tags                = var.tags

  profile {
    name = "cpu-based"

    capacity {
      default = var.web_instance_min
      minimum = var.web_instance_min
      maximum = var.web_instance_max
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

############################################
# App tier: fraud-detection service (private, backed up nightly)
############################################
resource "azurerm_network_interface" "fraud" {
  name                = "nic-${var.name}-fraud"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.app_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.fraud_detection_ip
  }
}

resource "azurerm_linux_virtual_machine" "fraud" {
  name                            = "vm-${var.name}-fraud"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.app_vm_size
  zone                            = local.zones == null ? null : local.zones[0]
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.fraud.id]
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  custom_data                     = base64encode(templatefile("${path.module}/cloud-init/fraud.yaml.tftpl", {}))
  tags                            = merge(var.tags, { tier = "app", service = "fraud-detection" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.workload_identity_id]
  }

  boot_diagnostics {}
}

############################################
# Monitoring hooks for this tier
############################################
resource "azurerm_monitor_metric_alert" "web_cpu" {
  name                = "alert-${var.name}-web-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_virtual_machine_scale_set.web.id]
  description         = "Web tier sustained CPU above 85% - autoscale may be at max."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "agw_unhealthy" {
  count               = local.use_agw ? 1 : 0
  name                = "alert-${var.name}-agw-unhealthy-hosts"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_gateway.this[0].id]
  description         = "Application Gateway reports unhealthy backend instances."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "UnhealthyHostCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_diagnostic_setting" "agw" {
  count                      = local.use_agw ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_application_gateway.this[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
