# =============================================================
# modules/management-groups/main.tf
# Management Group hierarchy for Algorhythm tenant
# =============================================================

data "azurerm_client_config" "current" {}

# Root MG sits directly under the tenant root
resource "azurerm_management_group" "root" {
  display_name               = "${var.org_name} (${var.org_prefix})"
  parent_management_group_id = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
}

resource "azurerm_management_group" "platform" {
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "workloads" {
  display_name               = "Workloads"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "workload_nonprod" {
  display_name               = "Non-Production"
  parent_management_group_id = azurerm_management_group.workloads.id
}

resource "azurerm_management_group" "workload_prod" {
  display_name               = "Production"
  parent_management_group_id = azurerm_management_group.workloads.id
}

# Subscription associations
resource "azurerm_management_group_subscription_association" "platform" {
  management_group_id = azurerm_management_group.platform.id
  subscription_id     = "/subscriptions/${var.platform_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "nonprod" {
  management_group_id = azurerm_management_group.workload_nonprod.id
  subscription_id     = "/subscriptions/${var.nonprod_subscription_id}"
}

resource "azurerm_management_group_subscription_association" "prod" {
  management_group_id = azurerm_management_group.workload_prod.id
  subscription_id     = "/subscriptions/${var.prod_subscription_id}"
}
