data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name   = "${var.project}-${var.environment}"
  suffix = random_string.suffix.result

  tags = merge({
    project     = "n-financial-bank-hybrid-cloud"
    environment = var.environment
    managed_by  = "terraform"
    repo        = "hybrid-cloud-migration-cicd-azure"
  }, var.tags)

  # Address plan mirrors the original Cisco Packet Tracer topology.
  azure_subnets = {
    GatewaySubnet    = "192.168.200.0/27" # VPN Gateway (name is mandated by Azure)
    AppGatewaySubnet = "192.168.201.0/24" # Application Gateway WAF
    web              = "192.168.202.0/24" # Public tier: customer portal VM Scale Set
    data             = "192.168.203.0/24" # Private tier: Azure SQL / Storage private endpoints
    app              = "192.168.204.0/24" # Private tier: fraud-detection service
  }

  onprem_subnets = {
    GatewaySubnet = "192.168.120.0/27" # Simulated on-prem VPN device
    managers      = "192.168.30.0/24"  # VLAN 30
    employees     = "192.168.40.0/24"  # VLAN 40
    core_banking  = "192.168.101.0/24" # Core banking server
    onprem_db     = "192.168.102.0/24" # On-prem database server
  }
}

############################################
# Resource groups: one for Azure, one for the on-prem simulation
############################################
resource "azurerm_resource_group" "azure" {
  name     = "rg-${local.name}-azure"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "onprem" {
  name     = "rg-${local.name}-onprem-sim"
  location = var.location
  tags     = merge(local.tags, { role = "simulated-on-premises" })
}

############################################
# Modules
############################################
module "monitoring" {
  source = "./modules/monitoring"

  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.azure.name
  resource_group_id   = azurerm_resource_group.azure.id
  subscription_id     = data.azurerm_client_config.current.subscription_id
  alert_email         = var.alert_email
  monthly_budget_usd  = var.monthly_budget_usd
  tags                = local.tags
}

module "network" {
  source = "./modules/network"

  name                   = local.name
  location               = var.location
  resource_group_name    = azurerm_resource_group.azure.name
  vnet_cidr              = var.azure_vnet_cidr
  subnets                = local.azure_subnets
  managers_cidr          = local.onprem_subnets.managers
  employees_cidr         = local.onprem_subnets.employees
  public_ingress_via_lb  = !var.enable_app_gateway_waf
  enable_ddos_protection = var.enable_ddos_protection
  tags                   = local.tags
}

module "onprem" {
  source = "./modules/onprem"

  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.onprem.name
  vnet_cidr           = var.onprem_vnet_cidr
  subnets             = local.onprem_subnets
  azure_vnet_cidr     = var.azure_vnet_cidr
  deploy_test_vms     = var.deploy_onprem_test_vms
  vm_size             = var.app_vm_size
  admin_username      = var.admin_username
  ssh_public_key      = module.security.ssh_public_key
  tags                = local.tags
}

module "connectivity" {
  source = "./modules/connectivity"

  name                       = local.name
  location                   = var.location
  mode                       = var.connectivity_mode
  azure_resource_group_name  = azurerm_resource_group.azure.name
  onprem_resource_group_name = azurerm_resource_group.onprem.name
  azure_vnet_id              = module.network.vnet_id
  azure_vnet_name            = module.network.vnet_name
  azure_vnet_cidr            = var.azure_vnet_cidr
  azure_gateway_subnet_id    = module.network.subnet_ids["GatewaySubnet"]
  onprem_vnet_id             = module.onprem.vnet_id
  onprem_vnet_name           = module.onprem.vnet_name
  onprem_vnet_cidr           = var.onprem_vnet_cidr
  onprem_gateway_subnet_id   = module.onprem.gateway_subnet_id
  availability_zones         = var.availability_zones
  tags                       = local.tags
}

module "security" {
  source = "./modules/security"

  name                       = local.name
  suffix                     = local.suffix
  location                   = var.location
  resource_group_name        = azurerm_resource_group.azure.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  deployer_object_id         = data.azurerm_client_config.current.object_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  enable_defender_for_cloud  = var.enable_defender_for_cloud
  tags                       = local.tags
}

module "compute" {
  source = "./modules/compute"

  name                       = local.name
  suffix                     = local.suffix
  location                   = var.location
  resource_group_name        = azurerm_resource_group.azure.name
  availability_zones         = var.availability_zones
  fraud_detection_ip         = cidrhost(local.azure_subnets.app, 10)
  web_subnet_id              = module.network.subnet_ids["web"]
  app_subnet_id              = module.network.subnet_ids["app"]
  appgw_subnet_id            = module.network.subnet_ids["AppGatewaySubnet"]
  enable_app_gateway_waf     = var.enable_app_gateway_waf
  web_vm_size                = var.web_vm_size
  app_vm_size                = var.app_vm_size
  web_instance_min           = var.web_instance_min
  web_instance_max           = var.web_instance_max
  admin_username             = var.admin_username
  ssh_public_key             = module.security.ssh_public_key
  workload_identity_id       = module.security.workload_identity_id
  key_vault_uri              = module.security.key_vault_uri
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  action_group_id            = module.monitoring.action_group_id
  tags                       = local.tags
}

module "data" {
  source = "./modules/data"

  name                = local.name
  suffix              = local.suffix
  location            = var.location
  resource_group_name = azurerm_resource_group.azure.name
  data_subnet_id      = module.network.subnet_ids["data"]
  dns_link_vnet_ids = {
    azure  = module.network.vnet_id
    onprem = module.onprem.vnet_id
  }
  sql_entra_admin_object_id  = data.azurerm_client_config.current.object_id
  sql_sku                    = var.sql_sku
  sql_admin_password         = module.security.sql_admin_password
  key_vault_id               = module.security.key_vault_id
  cmk_versionless_id         = module.security.cmk_versionless_id
  storage_replication        = var.storage_replication
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags

  depends_on = [module.security]
}

module "backup" {
  source = "./modules/backup"

  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.azure.name
  geo_redundant       = var.backup_geo_redundant
  protected_vm_ids = {
    fraud_detection = module.compute.fraud_detection_vm_id
  }
  tags = local.tags
}

module "edge" {
  source = "./modules/edge"
  count  = var.enable_front_door ? 1 : 0

  name                = local.name
  suffix              = local.suffix
  resource_group_name = azurerm_resource_group.azure.name
  origin_host         = module.compute.public_fqdn
  tags                = local.tags
}
