terraform {
  backend "azurerm" {
    resource_group_name  = "YOUR_ORG_PREFIX-tfstate-platform"
    storage_account_name = "YOUR_TFSTATE_SA_NAME"
    container_name       = "tfstate"
    key                  = "alz/shared/03-management/terraform.tfstate"
    use_oidc             = true
  }
}
