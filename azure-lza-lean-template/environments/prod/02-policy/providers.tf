provider "azurerm" {
  features {}
  use_oidc        = true
  subscription_id = var.platform_subscription_id
}
