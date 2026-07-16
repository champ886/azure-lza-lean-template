# =============================================================
# modules/avnm/main.tf
# Azure Virtual Network Manager
# Manages: peerings, security admin rules, routing config
# AVNM owns peerings and UDRs — workload modules have none
# =============================================================

data "azurerm_client_config" "current" {}

resource "azurerm_network_manager" "avnm" {
  name                = "avnm-${var.org_prefix}"
  location            = var.location
  resource_group_name = var.hub_rg_name
  tags                = var.tags

  scope {
    subscription_ids = [
      "/subscriptions/${var.platform_subscription_id}",
      "/subscriptions/${var.nonprod_subscription_id}",
      "/subscriptions/${var.prod_subscription_id}",
    ]
  }

  scope_accesses = ["Connectivity", "SecurityAdmin", "Routing"]
}

# ── Network Groups ────────────────────────────────────────────
resource "azurerm_network_manager_network_group" "dev_spokes" {
  name               = "ng-dev-spokes"
  network_manager_id = azurerm_network_manager.avnm.id
  description        = "All dev spoke VNets — dynamic membership via Azure Policy"
}

resource "azurerm_network_manager_network_group" "prod_spokes" {
  name               = "ng-prod-spokes"
  network_manager_id = azurerm_network_manager.avnm.id
  description        = "All prod spoke VNets — dynamic membership via Azure Policy"
}

resource "azurerm_network_manager_network_group" "all_spokes" {
  name               = "ng-all-spokes"
  network_manager_id = azurerm_network_manager.avnm.id
  description        = "All spoke VNets across all environments"
}

# Static members — add VNet IDs here as spokes are created
resource "azurerm_network_manager_static_member" "dev_workload" {
  count                     = length(var.dev_spoke_vnet_ids)
  name                      = "member-dev-spoke-${count.index}"
  network_group_id          = azurerm_network_manager_network_group.dev_spokes.id
  target_virtual_network_id = var.dev_spoke_vnet_ids[count.index]
}

resource "azurerm_network_manager_static_member" "prod_workload" {
  count                     = length(var.prod_spoke_vnet_ids)
  name                      = "member-prod-spoke-${count.index}"
  network_group_id          = azurerm_network_manager_network_group.prod_spokes.id
  target_virtual_network_id = var.prod_spoke_vnet_ids[count.index]
}

resource "azurerm_network_manager_static_member" "all_dev" {
  count                     = length(var.dev_spoke_vnet_ids)
  name                      = "member-all-dev-${count.index}"
  network_group_id          = azurerm_network_manager_network_group.all_spokes.id
  target_virtual_network_id = var.dev_spoke_vnet_ids[count.index]
}

resource "azurerm_network_manager_static_member" "all_prod" {
  count                     = length(var.prod_spoke_vnet_ids)
  name                      = "member-all-prod-${count.index}"
  network_group_id          = azurerm_network_manager_network_group.all_spokes.id
  target_virtual_network_id = var.prod_spoke_vnet_ids[count.index]
}

# ── Connectivity Configuration (hub-spoke topology) ───────────
resource "azurerm_network_manager_connectivity_configuration" "hub_spoke" {
  name                  = "cc-hub-spoke-${var.org_prefix}"
  network_manager_id    = azurerm_network_manager.avnm.id
  connectivity_topology = "HubAndSpoke"
  description           = "Hub-spoke topology managed by AVNM"

  hub {
    resource_id   = var.hub_vnet_id
    resource_type = "Microsoft.Network/virtualNetworks"
  }

  applies_to_group {
    group_connectivity  = "None"
    network_group_id    = azurerm_network_manager_network_group.all_spokes.id
    use_hub_gateway     = false
    global_mesh_enabled = false
  }
}

# ── Security Admin Configuration ──────────────────────────────
resource "azurerm_network_manager_security_admin_configuration" "main" {
  name               = "sac-${var.org_prefix}"
  network_manager_id = azurerm_network_manager.avnm.id
  description        = "Baseline security rules applied above NSGs to all spokes"
}

resource "azurerm_network_manager_admin_rule_collection" "baseline" {
  name                            = "arc-baseline"
  security_admin_configuration_id = azurerm_network_manager_security_admin_configuration.main.id
  description                     = "Baseline deny rules — cannot be overridden by spoke NSGs"

  network_group_ids = [azurerm_network_manager_network_group.all_spokes.id]
}

# Block RDP from internet — enforced above NSG layer
resource "azurerm_network_manager_admin_rule" "deny_rdp_internet" {
  name                     = "deny-rdp-internet"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.baseline.id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 100
  protocol                 = "Tcp"

  source {
    address_prefix_type = "ServiceTag"
    address_prefix      = "Internet"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination_port_ranges = ["3389"]
}

# Block SSH from internet
resource "azurerm_network_manager_admin_rule" "deny_ssh_internet" {
  name                     = "deny-ssh-internet"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.baseline.id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 110
  protocol                 = "Tcp"

  source {
    address_prefix_type = "ServiceTag"
    address_prefix      = "Internet"
  }
  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = "*"
  }
  destination_port_ranges = ["22"]
}

# ── Routing Configuration — push default route to all spokes ──
# This is the key: when router_vm_ip changes to ILB frontend IP
# in Phase 2, AVNM propagates the updated route to all spoke
# subnets automatically — zero spoke changes needed
resource "azurerm_network_manager_routing_configuration" "default_route" {
  name               = "rc-default-route-${var.org_prefix}"
  network_manager_id = azurerm_network_manager.avnm.id
  description        = "Push default route to all spokes via hub router/NVA"
}

resource "azurerm_network_manager_routing_rule_collection" "spokes" {
  name                          = "rrc-spokes"
  routing_configuration_id      = azurerm_network_manager_routing_configuration.default_route.id
  local_route_setting           = "DirectRoutingWithinVNet"

  applies_to_group {
    network_group_id = azurerm_network_manager_network_group.all_spokes.id
  }
}

# Default route → router VM (Phase 1) / ILB frontend (Phase 2)
resource "azurerm_network_manager_routing_rule" "default_to_nva" {
  name                       = "default-to-hub-nva"
  routing_rule_collection_id = azurerm_network_manager_routing_rule_collection.spokes.id
  destination_type           = "AddressPrefix"

  destination {
    type        = "AddressPrefix"
    destination = "0.0.0.0/0"
  }

  next_hop {
    next_hop_type            = "VirtualAppliance"
    next_hop_ip_address      = var.nva_next_hop_ip  # Phase 1: router_vm_ip / Phase 2: ilb_frontend_ip
  }
}

# RFC1918 E-W via hub NVA
resource "azurerm_network_manager_routing_rule" "rfc1918_10" {
  name                       = "rfc1918-10-to-nva"
  routing_rule_collection_id = azurerm_network_manager_routing_rule_collection.spokes.id

  destination {
    type        = "AddressPrefix"
    destination = "10.0.0.0/8"
  }

  next_hop {
    next_hop_type       = "VirtualAppliance"
    next_hop_ip_address = var.nva_next_hop_ip
  }
}

# ── Deployment (commit configurations) ───────────────────────
resource "azurerm_network_manager_deployment" "connectivity" {
  network_manager_id = azurerm_network_manager.avnm.id
  location           = var.location
  scope_access       = "Connectivity"
  configuration_ids  = [azurerm_network_manager_connectivity_configuration.hub_spoke.id]
  triggers           = { config_hash = azurerm_network_manager_connectivity_configuration.hub_spoke.id }
}

resource "azurerm_network_manager_deployment" "security" {
  network_manager_id = azurerm_network_manager.avnm.id
  location           = var.location
  scope_access       = "SecurityAdmin"
  configuration_ids  = [azurerm_network_manager_security_admin_configuration.main.id]
  triggers           = { config_hash = azurerm_network_manager_security_admin_configuration.main.id }
}

resource "azurerm_network_manager_deployment" "routing" {
  network_manager_id = azurerm_network_manager.avnm.id
  location           = var.location
  scope_access       = "Routing"
  configuration_ids  = [azurerm_network_manager_routing_configuration.default_route.id]
  triggers           = { config_hash = var.nva_next_hop_ip }
}
