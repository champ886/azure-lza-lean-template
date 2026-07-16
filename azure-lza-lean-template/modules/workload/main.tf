# =============================================================
# modules/workload/main.tf
# Spoke VNet — subnets, NSGs, private endpoints, Key Vault
# NO peering resources — AVNM owns them
# NO UDR resources — AVNM routing config pushes them
# =============================================================

resource "azurerm_resource_group" "workload" {
  name     = "rg-workload-${var.environment}-${var.org_prefix}"
  location = var.location
  tags     = var.tags
}

# ── Spoke VNet ───────────────────────────────────────────────
resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-${var.environment}-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  address_space       = [var.spoke_address_space]
  tags                = var.tags
}

# ── Subnets ───────────────────────────────────────────────────
resource "azurerm_subnet" "workload" {
  name                 = "WorkloadSubnet"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.workload_subnet_cidr]

  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.Storage",
    "Microsoft.ContainerRegistry",
  ]
}

resource "azurerm_subnet" "aks" {
  name                 = "AKSSubnet"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.aks_subnet_cidr]

  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.Storage",
    "Microsoft.ContainerRegistry",
  ]
}

resource "azurerm_subnet" "pe" {
  name                 = "PrivateEndpointSubnet"
  resource_group_name  = azurerm_resource_group.workload.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.pe_subnet_cidr]
  private_endpoint_network_policies_enabled = false
}

# ── NSGs ──────────────────────────────────────────────────────
resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-${var.environment}-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = var.tags

  security_rule {
    name                       = "deny-direct-internet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-lb-inbound"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${var.environment}-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  tags                = var.tags

  security_rule {
    name                       = "deny-direct-internet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-aks-nodeport"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 210
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# ── Key Vault — private endpoint, no public access ───────────
resource "azurerm_key_vault" "spoke" {
  name                          = "kv-${var.environment}-${var.org_prefix}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.workload.name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = var.environment == "prod" ? true : false
  soft_delete_retention_days    = var.environment == "prod" ? 90 : 7
  enable_rbac_authorization     = true
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [
      azurerm_subnet.workload.id,
      azurerm_subnet.aks.id,
    ]
  }
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-${var.environment}-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-${var.environment}"
    private_connection_resource_id = azurerm_key_vault.spoke.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns-group"
    private_dns_zone_ids = [var.dns_zone_vault_id]
  }
}

# ── Private Endpoint — ACR ────────────────────────────────────
resource "azurerm_private_endpoint" "acr" {
  count               = var.acr_id != "" ? 1 : 0
  name                = "pe-acr-${var.environment}-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-acr-${var.environment}"
    private_connection_resource_id = var.acr_id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-group"
    private_dns_zone_ids = [var.dns_zone_acr_id]
  }
}

# ── Private Endpoint — Storage (tfstate SA) ───────────────────
resource "azurerm_private_endpoint" "storage" {
  count               = var.storage_account_id != "" ? 1 : 0
  name                = "pe-sa-${var.environment}-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.workload.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sa-${var.environment}"
    private_connection_resource_id = var.storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sa-dns-group"
    private_dns_zone_ids = [var.dns_zone_blob_id]
  }
}

# ── Private DNS Zone VNet Links ───────────────────────────────
# Links all privatelink zones to this spoke VNet
# so PE FQDNs resolve inside the spoke

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob-${var.environment}"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = var.dns_zone_blob_name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
  provider              = azurerm.platform
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "link-vault-${var.environment}"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = var.dns_zone_vault_name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
  provider              = azurerm.platform
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr-${var.environment}"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = var.dns_zone_acr_name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
  provider              = azurerm.platform
}

resource "azurerm_private_dns_zone_virtual_network_link" "monitor" {
  name                  = "link-monitor-${var.environment}"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = var.dns_zone_monitor_name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = var.tags
  provider              = azurerm.platform
}

# ── NSG Flow Logs ─────────────────────────────────────────────
resource "azurerm_network_watcher_flow_log" "workload" {
  network_watcher_name = "NetworkWatcher_${var.location}"
  resource_group_name  = "NetworkWatcherRG"
  name                 = "flowlog-workload-${var.environment}-${var.org_prefix}"

  network_security_group_id = azurerm_network_security_group.workload.id
  storage_account_id        = var.flow_log_storage_account_id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = var.law_workspace_guid
    workspace_region      = var.location
    workspace_resource_id = var.law_workspace_id
    interval_in_minutes   = 10
  }

  tags = var.tags
}
