# Azure Kubernetes Service for the containerised fraud-detection API.
#
#   - Free control-plane tier, one small autoscaling node pool (cost)
#   - Azure CNI Overlay + Cilium data plane and network policies
#   - Entra ID authentication + Azure RBAC; local admin account disabled
#   - OIDC issuer + workload identity, Key Vault CSI driver with rotation
#   - Egress through the existing NAT Gateway; internal LBs land in snet-aks
#   - Container Insights (cost-optimised streams) + kube-audit logs
#   - Azure Policy add-on with Kubernetes guardrails assigned below

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-${var.name}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# The control plane manages internal load balancers and validates the NAT
# Gateway on the node subnet, so it needs network rights there before create.
resource "azurerm_role_assignment" "aks_subnet" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${var.name}"
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "rg-${var.name}-aks-nodes"
  sku_tier            = "Free"
  tags                = var.tags

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  image_cleaner_enabled             = true
  image_cleaner_interval_hours      = 48

  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    vnet_subnet_id              = var.subnet_id
    zones                       = var.availability_zones
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    max_pods                    = 50
    os_sku                      = "AzureLinux"
    os_disk_size_gb             = 30
    temporary_name_for_rotation = "systemtmp"
    tags                        = var.tags

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    outbound_type       = "userAssignedNATGateway"
    load_balancer_sku   = "standard"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  lifecycle {
    ignore_changes = [
      # The autoscaler owns the node count.
      default_node_pool[0].node_count,
      # Patch upgrades are automatic (automatic_upgrade_channel = "patch").
      kubernetes_version,
    ]
  }

  depends_on = [azurerm_role_assignment.aks_subnet]
}

# Cluster access is Entra ID only; grant the deployer (and any extra admins).
resource "azurerm_role_assignment" "cluster_admin" {
  for_each             = toset(var.admin_object_ids)
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

############################################
# Container Insights (managed identity auth needs a DCR + association).
# Only the cost-optimised streams are collected; the workspace daily cap
# still applies.
############################################
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.location}-aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "ciworkspace"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "5m"
          namespaceFilteringMode = "Exclude"
          namespaces             = ["kube-system", "gatekeeper-system"]
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
}

# Control-plane audit trail (who changed what in the cluster).
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "guard"
  }
}

############################################
# Kubernetes guardrails via the Azure Policy add-on (Gatekeeper).
# Built-in definitions are looked up by their fixed GUIDs so a wrong ID fails
# at plan time instead of silently doing nothing.
############################################
data "azurerm_policy_definition" "k8s_no_privileged" {
  name = "95edb821-ddaf-4404-9732-666045e056b4" # Kubernetes cluster should not allow privileged containers
}

data "azurerm_policy_definition" "k8s_readonly_rootfs" {
  name = "df49d893-a74c-421d-bc95-c663042e5b80" # Kubernetes cluster containers should run with a read only root file system
}

resource "azurerm_resource_policy_assignment" "k8s_no_privileged" {
  name                 = "aks-deny-privileged"
  display_name         = "AKS: deny privileged containers"
  resource_id          = azurerm_kubernetes_cluster.this.id
  policy_definition_id = data.azurerm_policy_definition.k8s_no_privileged.id
  parameters           = jsonencode({ effect = { value = "deny" } })
}

resource "azurerm_resource_policy_assignment" "k8s_readonly_rootfs" {
  name                 = "aks-audit-readonly-rootfs"
  display_name         = "AKS: audit containers without a read-only root filesystem"
  resource_id          = azurerm_kubernetes_cluster.this.id
  policy_definition_id = data.azurerm_policy_definition.k8s_readonly_rootfs.id
  parameters           = jsonencode({ effect = { value = "audit" } })
}
