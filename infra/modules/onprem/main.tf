# Simulated on-premises data centre.
# A real bank would terminate the tunnel on a physical firewall/router.
# Here a separate VNet (own resource group) plays that role so the whole
# hybrid design - VLANs, ACLs and the IPsec tunnel - can be proven end-to-end
# in a single Azure subscription.

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}-onprem"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each                        = var.subnets
  name                            = each.key == "GatewaySubnet" ? "GatewaySubnet" : "snet-${replace(each.key, "_", "-")}"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [each.value]
  default_outbound_access_enabled = each.key == "GatewaySubnet"
}

############################################
# NSGs = the Cisco ACLs from the Packet Tracer lab
############################################
locals {
  mgr = var.subnets["managers"]
  emp = var.subnets["employees"]
  db  = var.subnets["onprem_db"]

  rules = {
    managers = [
      # ACL 130 - Deny Employee VLAN (40) accessing Manager VLAN (30)
      { name = "Deny-Employees-ACL130", priority = 100, direction = "Inbound", access = "Deny", src = local.emp, dst = local.mgr, port = "*" },
    ]
    employees = [
      # ACL 140 - Deny Manager VLAN accessing Employee VLAN
      { name = "Deny-Managers-ACL140", priority = 100, direction = "Inbound", access = "Deny", src = local.mgr, dst = local.emp, port = "*" },
      # "All Employees cannot access cloud resources"
      { name = "Deny-Employees-to-Azure", priority = 100, direction = "Outbound", access = "Deny", src = local.emp, dst = var.azure_vnet_cidr, port = "*" },
    ]
    onprem_db = [
      # ACL 120 - Permit Employee & Manager VLANs to on-prem DB, deny all else
      { name = "Allow-Managers-DB-ACL120", priority = 100, direction = "Inbound", access = "Allow", src = local.mgr, dst = local.db, port = "1433" },
      { name = "Allow-Employees-DB-ACL120", priority = 110, direction = "Inbound", access = "Allow", src = local.emp, dst = local.db, port = "1433" },
      { name = "Allow-AzureLoadBalancer", priority = 200, direction = "Inbound", access = "Allow", src = "AzureLoadBalancer", dst = "*", port = "*" },
      { name = "Deny-All-Inbound", priority = 4096, direction = "Inbound", access = "Deny", src = "*", dst = "*", port = "*" },
    ]
    core_banking = [
      { name = "Allow-Staff-HTTPS", priority = 100, direction = "Inbound", access = "Allow", src = var.vnet_cidr, dst = var.subnets["core_banking"], port = "443" },
      { name = "Allow-AzureLoadBalancer", priority = 200, direction = "Inbound", access = "Allow", src = "AzureLoadBalancer", dst = "*", port = "*" },
      { name = "Deny-All-Inbound", priority = 4096, direction = "Inbound", access = "Deny", src = "*", dst = "*", port = "*" },
    ]
  }
}

resource "azurerm_network_security_group" "this" {
  for_each            = local.rules
  name                = "nsg-${var.name}-onprem-${replace(each.key, "_", "-")}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = each.value
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = security_rule.value.src
      destination_address_prefix = security_rule.value.dst
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.rules
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

############################################
# Test VMs (Manager PC, Employee PC, on-prem DB server)
############################################
locals {
  test_vms = var.deploy_test_vms ? {
    manager-pc  = { subnet = "managers", ip = cidrhost(local.mgr, 10), init = null }
    employee-pc = { subnet = "employees", ip = cidrhost(local.emp, 10), init = null }
    onprem-db = {
      subnet = "onprem_db"
      ip     = cidrhost(local.db, 10)
      # Stand-in for the on-prem database: a TCP listener on 1433.
      init = <<-EOT
        #cloud-config
        write_files:
          - path: /opt/fake-sql.py
            content: |
              import socket
              s = socket.socket()
              s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
              s.bind(("0.0.0.0", 1433))
              s.listen(50)
              while True:
                  conn, _ = s.accept()
                  conn.close()
          - path: /etc/systemd/system/fake-sql.service
            content: |
              [Unit]
              Description=On-prem DB stand-in (TCP 1433)
              After=network.target
              [Service]
              ExecStart=/usr/bin/python3 /opt/fake-sql.py
              Restart=always
              [Install]
              WantedBy=multi-user.target
        runcmd:
          - systemctl daemon-reload
          - systemctl enable --now fake-sql.service
      EOT
    }
  } : {}
}

resource "azurerm_network_interface" "test" {
  for_each            = local.test_vms
  name                = "nic-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this[each.value.subnet].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  for_each                        = local.test_vms
  name                            = "vm-${each.key}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.test[each.key].id]
  custom_data                     = each.value.init == null ? null : base64encode(each.value.init)
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
