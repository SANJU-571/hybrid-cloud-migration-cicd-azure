# Hybrid connectivity between the (simulated) on-premises network and Azure.
#   mode = "vpn"     -> Route-based IPsec Site-to-Site VPN (production design)
#   mode = "peering" -> VNet peering (same routing outcome, near-zero cost; lab default)

locals {
  vpn = var.mode == "vpn"

  sides = local.vpn ? {
    azure = {
      rg        = var.azure_resource_group_name
      subnet_id = var.azure_gateway_subnet_id
    }
    onprem = {
      rg        = var.onprem_resource_group_name
      subnet_id = var.onprem_gateway_subnet_id
    }
  } : {}

  # The "remote" side as seen from each gateway
  remote = {
    azure  = { peer = "onprem", cidr = var.onprem_vnet_cidr }
    onprem = { peer = "azure", cidr = var.azure_vnet_cidr }
  }
}

############################################
# Option A: IPsec Site-to-Site VPN
############################################
resource "random_password" "psk" {
  count   = local.vpn ? 1 : 0
  length  = 32
  special = false
}

resource "azurerm_public_ip" "gw" {
  for_each            = local.sides
  name                = "pip-${var.name}-vpngw-${each.key}"
  location            = var.location
  resource_group_name = each.value.rg
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.availability_zones) > 0 ? var.availability_zones : null
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "this" {
  for_each            = local.sides
  name                = "vpngw-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = each.value.rg
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = length(var.availability_zones) > 0 ? "VpnGw1AZ" : "VpnGw1"
  generation          = "Generation1"
  active_active       = false
  tags                = var.tags

  ip_configuration {
    name                          = "gwipconfig"
    public_ip_address_id          = azurerm_public_ip.gw[each.key].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = each.value.subnet_id
  }
}

# Each side describes the other as a "local network gateway"
resource "azurerm_local_network_gateway" "this" {
  for_each            = local.sides
  name                = "lng-${var.name}-to-${local.remote[each.key].peer}"
  location            = var.location
  resource_group_name = each.value.rg
  gateway_address     = azurerm_public_ip.gw[local.remote[each.key].peer].ip_address
  address_space       = [local.remote[each.key].cidr]
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "this" {
  for_each                   = local.sides
  name                       = "cn-${var.name}-${each.key}-to-${local.remote[each.key].peer}"
  location                   = var.location
  resource_group_name        = each.value.rg
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.this[each.key].id
  local_network_gateway_id   = azurerm_local_network_gateway.this[each.key].id
  shared_key                 = random_password.psk[0].result
  connection_protocol        = "IKEv2"
  tags                       = var.tags

  # Bank-grade crypto policy instead of Azure defaults
  ipsec_policy {
    dh_group         = "DHGroup14"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS2048"
    sa_lifetime      = 27000
  }
}

############################################
# Option B: VNet peering (lab / low cost)
############################################
resource "azurerm_virtual_network_peering" "azure_to_onprem" {
  count                     = local.vpn ? 0 : 1
  name                      = "peer-azure-to-onprem"
  resource_group_name       = var.azure_resource_group_name
  virtual_network_name      = var.azure_vnet_name
  remote_virtual_network_id = var.onprem_vnet_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "onprem_to_azure" {
  count                     = local.vpn ? 0 : 1
  name                      = "peer-onprem-to-azure"
  resource_group_name       = var.onprem_resource_group_name
  virtual_network_name      = var.onprem_vnet_name
  remote_virtual_network_id = var.azure_vnet_id
  allow_forwarded_traffic   = true
}
