provider "azurerm" {
  features {}
  use_oidc        = true
  subscription_id = var.workload_subscription_id
}
