# =============================================================
# modules/policy/main.tf
# Azure Policy assignments — NSG DINE + security Deny rules
# Assigned at MG scope so all child subs inherit
# =============================================================

# ── Built-in: Deploy NSG if subnet has none (DINE) ──────────
resource "azurerm_management_group_policy_assignment" "nsg_dine" {
  name                 = "deploy-nsg-subnets"
  display_name         = "Deploy NSG to subnets without one"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/2f9f7db5-4568-4e0c-b318-bd10c8b74af4"
  management_group_id  = var.management_group_id
  location             = var.location

  identity { type = "SystemAssigned" }

  parameters = jsonencode({
    effect = { value = "DeployIfNotExists" }
  })
}

# ── Built-in: Deny RDP from internet ────────────────────────
resource "azurerm_management_group_policy_assignment" "deny_rdp" {
  name                 = "deny-rdp-internet"
  display_name         = "Deny RDP access from internet"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e372f825-a257-4fb8-9175-797a8a8627d4"
  management_group_id  = var.management_group_id

  parameters = jsonencode({
    effect = { value = "Deny" }
  })
}

# ── Built-in: Deny SSH from internet ────────────────────────
resource "azurerm_management_group_policy_assignment" "deny_ssh" {
  name                 = "deny-ssh-internet"
  display_name         = "Deny SSH access from internet"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/2c89a2e5-7285-40fe-afe0-ae8654b92fb2"
  management_group_id  = var.management_group_id

  parameters = jsonencode({
    effect = { value = "Deny" }
  })
}

# ── Built-in: Require NSG flow logs ─────────────────────────
resource "azurerm_management_group_policy_assignment" "nsg_flow_logs" {
  name                 = "require-nsg-flow-logs"
  display_name         = "Audit NSGs without flow logs"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/27960feb-a23c-4577-8d36-ef8b5f35e0be"
  management_group_id  = var.management_group_id

  parameters = jsonencode({
    effect = { value = var.policy_mode == "enforce" ? "DeployIfNotExists" : "Audit" }
  })
}

# ── Prod-only: Deny public IP on NICs ───────────────────────
resource "azurerm_management_group_policy_assignment" "deny_public_ip" {
  count                = var.deny_public_ips ? 1 : 0
  name                 = "deny-public-ip-nic"
  display_name         = "Deny public IP on VM NICs"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-ddc1adde0c2d"
  management_group_id  = var.management_group_id

  parameters = jsonencode({
    effect = { value = "Deny" }
  })
}

# ── Role assignment for DINE remediation ────────────────────
resource "azurerm_role_assignment" "nsg_dine_contributor" {
  scope                = var.management_group_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_management_group_policy_assignment.nsg_dine.identity[0].principal_id
}
