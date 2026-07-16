provider "azurerm" {
  features {}
  use_oidc        = true
  subscription_id = var.workload_subscription_id
}

provider "azurerm" {
  alias           = "platform"
  features {}
  use_oidc        = true
  subscription_id = var.platform_subscription_id
}
