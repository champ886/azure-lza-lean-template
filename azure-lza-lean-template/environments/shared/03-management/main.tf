# environments/shared/03-management/main.tf
# Deploys first — no dependency on hub state
# management_subnet_id wired up in phase 2 after hub is deployed

data "azurerm_client_config" "current" {}

module "management" {
  source = "../../../modules/management"

  org_prefix               = var.org_prefix
  location                 = var.location
  law_retention_days       = var.law_retention_days
  budget_amount            = var.budget_amount
  defender_tier            = var.defender_tier
  security_email           = var.security_email
  platform_subscription_id = var.platform_subscription_id

  # Empty on first deploy — hub subnet doesn't exist yet
  # After hub is deployed run: terraform apply -var-file=terraform.tfvars
  # with management_subnet_id set in terraform.tfvars to wire up LAW private endpoint
  management_subnet_id = var.management_subnet_id

  tags = {
    Environment = "shared"
    ManagedBy   = "Terraform"
    Layer       = "03-management"
    OrgPrefix   = var.org_prefix
  }
}
