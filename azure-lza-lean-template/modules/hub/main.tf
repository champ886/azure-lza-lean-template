# =============================================================
# modules/hub/main.tf
# Shared hub VNet — all subnets pre-declared, NAT GW, router VM
# Phase 1: router VM as UDR next hop
# Phase 2: replace router VM with OPNsense + ILB (one var flip)
# =============================================================

resource "azurerm_resource_group" "hub" {
  name     = "rg-hub-${var.org_prefix}"
  location = var.location
  tags     = var.tags
}

# ── Hub VNet ─────────────────────────────────────────────────
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.hub_address_space]
  tags                = var.tags
}

# ── Subnets — all pre-declared at zero cost ──────────────────
resource "azurerm_subnet" "nva" {
  name                 = "NVASubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.nva_subnet_cidr]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_cidr]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

resource "azurerm_subnet" "management" {
  name                 = "ManagementSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.management_subnet_cidr]
}

resource "azurerm_subnet" "nat_gw" {
  name                 = "NATGatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.nat_gw_subnet_cidr]
}

# ── NSG — NVA Subnet ─────────────────────────────────────────
resource "azurerm_network_security_group" "nva" {
  name                = "nsg-nva-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  tags                = var.tags

  security_rule {
    name                       = "allow-spoke-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-mgmt-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.management_subnet_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nva" {
  subnet_id                 = azurerm_subnet.nva.id
  network_security_group_id = azurerm_network_security_group.nva.id
}

# ── NSG — Management Subnet ───────────────────────────────────
resource "azurerm_network_security_group" "management" {
  name                = "nsg-mgmt-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  tags                = var.tags

  security_rule {
    name                       = "allow-bastion-rdp-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = var.bastion_subnet_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

# ── Public IP for NAT Gateway ─────────────────────────────────
resource "azurerm_public_ip" "nat_gw" {
  name                = "pip-natgw-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ── NAT Gateway — shared egress for all spokes ───────────────
resource "azurerm_nat_gateway" "hub" {
  name                    = "natgw-hub-${var.org_prefix}"
  location                = var.location
  resource_group_name     = azurerm_resource_group.hub.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "hub" {
  nat_gateway_id       = azurerm_nat_gateway.hub.id
  public_ip_address_id = azurerm_public_ip.nat_gw.id
}

resource "azurerm_subnet_nat_gateway_association" "nat_gw" {
  subnet_id      = azurerm_subnet.nat_gw.id
  nat_gateway_id = azurerm_nat_gateway.hub.id
}

# ── Router VM — Phase 1 next hop ─────────────────────────────
# Lightweight B1s VM with IP forwarding ON
# Acts as UDR target for all spoke subnets
# Phase 2: remove this, deploy OPNsense + ILB into NVASubnet
#          AVNM routing config updates next hop automatically

resource "azurerm_network_interface" "router" {
  name                          = "nic-router-${var.org_prefix}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.hub.name
  enable_ip_forwarding          = true   # CRITICAL — must be true
  enable_accelerated_networking = false  # not supported on B1s
  tags                          = var.tags

  ip_configuration {
    name                          = "ipconfig-router"
    subnet_id                     = azurerm_subnet.nva.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.router_vm_ip   # e.g. 10.2.1.4
  }
}

resource "azurerm_linux_virtual_machine" "router" {
  name                  = "vm-router-${var.org_prefix}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.hub.name
  size                  = "Standard_B1s"
  admin_username        = "routeradmin"
  tags                  = var.tags

  network_interface_ids = [azurerm_network_interface.router.id]

  admin_ssh_key {
    username   = "routeradmin"
    public_key = var.router_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Enable IP forwarding at OS level via cloud-init
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    runcmd:
      - sysctl -w net.ipv4.ip_forward=1
      - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
      - sysctl -p
  CLOUDINIT
  )

  boot_diagnostics {}
}

# ── Diagnostic settings ───────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "hub_vnet" {
  name                       = "diag-hub-vnet-${var.org_prefix}"
  target_resource_id         = azurerm_virtual_network.hub.id
  log_analytics_workspace_id = var.law_workspace_id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
