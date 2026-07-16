# =============================================================
# modules/management/main.tf
# Shared management resources — LAW, Defender, Budgets
# Lives in sub-platform-prod, shared across all environments
# =============================================================

resource "azurerm_resource_group" "management" {
  name     = "rg-management-${var.org_prefix}"
  location = var.location
  tags     = var.tags
}

# ── Log Analytics Workspace ───────────────────────────────────
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.org_prefix}-platform"
  location            = var.location
  resource_group_name = azurerm_resource_group.management.name
  sku                 = "PerGB2018"
  retention_in_days   = var.law_retention_days
  tags                = var.tags
}

# ── Azure Monitor Private Link Scope (AMPLS) ──────────────────
# Groups LAW under a single private endpoint for ingestion
resource "azurerm_monitor_private_link_scope" "law" {
  name                = "ampls-${var.org_prefix}"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_monitor_private_link_scoped_service" "law" {
  name                = "ampls-law-link"
  resource_group_name = azurerm_resource_group.management.name
  scope_name          = azurerm_monitor_private_link_scope.law.name
  linked_resource_id  = azurerm_log_analytics_workspace.law.id
}

# ── Private Endpoint for LAW ──────────────────────────────────
# Optional on first deploy — management_subnet_id is empty until
# hub is deployed. Set management_subnet_id in terraform.tfvars
# after hub apply and re-apply this layer to wire up the PE.
resource "azurerm_private_endpoint" "law" {
  count               = var.management_subnet_id != "" ? 1 : 0
  name                = "pe-law-${var.org_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.management.name
  subnet_id           = var.management_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-law"
    private_connection_resource_id = azurerm_monitor_private_link_scope.law.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "law-dns-group"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.monitor.id,
      azurerm_private_dns_zone.oms.id,
      azurerm_private_dns_zone.ods.id,
      azurerm_private_dns_zone.agentsvc.id,
    ]
  }
}

# ── Private DNS Zones ─────────────────────────────────────────
# Created once here in the management layer and linked to all
# spoke VNets in the workload module so PE FQDNs resolve privately
resource "azurerm_private_dns_zone" "monitor" {
  name                = "privatelink.monitor.azure.com"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "oms" {
  name                = "privatelink.oms.opinsights.azure.com"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "ods" {
  name                = "privatelink.ods.opinsights.azure.com"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "agentsvc" {
  name                = "privatelink.agentsvc.azure-automation.net"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.management.name
  tags                = var.tags
}

# ── Microsoft Defender for Cloud ──────────────────────────────
# Enables Defender plans on the platform subscription
# defender_tier = "Free" or "Standard"
resource "azurerm_security_center_subscription_pricing" "servers" {
  tier          = var.defender_tier
  resource_type = "VirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "containers" {
  tier          = var.defender_tier
  resource_type = "Containers"
  depends_on    = [azurerm_security_center_subscription_pricing.servers]
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  tier          = var.defender_tier
  resource_type = "StorageAccounts"
  depends_on    = [azurerm_security_center_subscription_pricing.containers]
}

resource "azurerm_security_center_contact" "main" {
  email               = var.security_email
  alert_notifications = "On"
  alerts_to_admins    = "On"
}

# ── Budget alerts ─────────────────────────────────────────────
# Sends email alerts at 80% and 100% of monthly budget
resource "azurerm_consumption_budget_subscription" "platform" {
  name            = "budget-platform-${var.org_prefix}"
  subscription_id = "/subscriptions/${var.platform_subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    contact_emails = [var.security_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    contact_emails = [var.security_email]
  }

  lifecycle { ignore_changes = [time_period] }
}
