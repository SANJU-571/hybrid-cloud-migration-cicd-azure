############################################
# DDoS (optional - expensive)
############################################
resource "azurerm_network_ddos_protection_plan" "this" {
  count               = var.enable_ddos_protection ? 1 : 0
  name                = "ddos-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

############################################
# Virtual Network
############################################
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}-azure"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = var.tags

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.this[0].id
      enable = true
    }
  }
}

resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = contains(["GatewaySubnet", "AppGatewaySubnet"], each.key) ? each.key : "snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]

  # Workload subnets are private (no implicit internet egress); the web and
  # app tiers get controlled outbound access through the NAT Gateway below.
  # Gateway subnets keep the platform default the managed gateways expect.
  default_outbound_access_enabled = contains(["GatewaySubnet", "AppGatewaySubnet"], each.key)

  private_endpoint_network_policies = each.key == "data" ? "Enabled" : "Disabled"
}

############################################
# NAT Gateway - deterministic outbound internet for patching (web, app and AKS subnets)
############################################
resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "ng-${var.name}"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  # snet-aks egresses through the same NAT Gateway (AKS outbound_type = userAssignedNATGateway).
  for_each       = toset([for k in ["web", "app", "aks"] : k if contains(keys(var.subnets), k)])
  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

############################################
# Network Security Groups
# These translate the Cisco ACLs from the Packet Tracer design:
#   ACL 110 - only the Manager VLAN may reach the cloud database
#   (Employees cannot access cloud resources)
############################################
locals {
  web = var.subnets["web"]
  app = var.subnets["app"]
  dat = var.subnets["data"]
  agw = var.subnets["AppGatewaySubnet"]

  nsg_rules = {
    AppGatewaySubnet = [
      { name = "Allow-GatewayManager", priority = 100, access = "Allow", protocol = "Tcp", src = "GatewayManager", dst = "*", ports = ["65200-65535"] },
      { name = "Allow-AzureLoadBalancer", priority = 110, access = "Allow", protocol = "*", src = "AzureLoadBalancer", dst = "*", ports = ["*"] },
      { name = "Allow-Internet-HTTP", priority = 120, access = "Allow", protocol = "Tcp", src = "Internet", dst = "*", ports = ["80", "443"] },
    ]
    web = concat(
      var.public_ingress_via_lb ? [
        { name = "Allow-Internet-HTTP", priority = 100, access = "Allow", protocol = "Tcp", src = "Internet", dst = local.web, ports = ["80"] },
        ] : [
        { name = "Allow-AppGateway-HTTP", priority = 100, access = "Allow", protocol = "Tcp", src = local.agw, dst = local.web, ports = ["80"] },
      ],
      [
        { name = "Allow-AzureLoadBalancer", priority = 110, access = "Allow", protocol = "*", src = "AzureLoadBalancer", dst = "*", ports = ["*"] },
        { name = "Allow-Managers-SSH", priority = 200, access = "Allow", protocol = "Tcp", src = var.managers_cidr, dst = local.web, ports = ["22"] },
        { name = "Deny-All-Inbound", priority = 4096, access = "Deny", protocol = "*", src = "*", dst = "*", ports = ["*"] },
      ]
    )
    app = [
      { name = "Allow-Web-to-FraudAPI", priority = 100, access = "Allow", protocol = "Tcp", src = local.web, dst = local.app, ports = ["8080"] },
      { name = "Allow-Managers-SSH", priority = 200, access = "Allow", protocol = "Tcp", src = var.managers_cidr, dst = local.app, ports = ["22"] },
      { name = "Allow-AzureLoadBalancer", priority = 300, access = "Allow", protocol = "*", src = "AzureLoadBalancer", dst = "*", ports = ["*"] },
      { name = "Deny-All-Inbound", priority = 4096, access = "Deny", protocol = "*", src = "*", dst = "*", ports = ["*"] },
    ]
    data = [
      # ACL 110 - Permit Manager VLAN to cloud DB, deny everything else
      { name = "Allow-Managers-SQL-ACL110", priority = 100, access = "Allow", protocol = "Tcp", src = var.managers_cidr, dst = local.dat, ports = ["1433"] },
      { name = "Allow-AppTier-SQL", priority = 110, access = "Allow", protocol = "Tcp", src = local.app, dst = local.dat, ports = ["1433"] },
      { name = "Allow-WebTier-SQL", priority = 120, access = "Allow", protocol = "Tcp", src = local.web, dst = local.dat, ports = ["1433"] },
      { name = "Allow-AppTier-Blob", priority = 130, access = "Allow", protocol = "Tcp", src = local.app, dst = local.dat, ports = ["443"] },
      { name = "Deny-Employees-ACL110", priority = 400, access = "Deny", protocol = "*", src = var.employees_cidr, dst = "*", ports = ["*"] },
      { name = "Deny-All-Inbound", priority = 4096, access = "Deny", protocol = "*", src = "*", dst = "*", ports = ["*"] },
    ]
  }
}

resource "azurerm_network_security_group" "this" {
  for_each            = local.nsg_rules
  name                = "nsg-${var.name}-${lower(each.key)}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = each.value
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = length(security_rule.value.ports) == 1 ? security_rule.value.ports[0] : null
      destination_port_ranges    = length(security_rule.value.ports) > 1 ? security_rule.value.ports : null
      source_address_prefix      = security_rule.value.src
      destination_address_prefix = security_rule.value.dst
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.nsg_rules
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}
