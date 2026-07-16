# environments/prod/02-policy/main.tf
data "terraform_remote_state" "mg" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/dev/01-management-groups/terraform.tfstate"
  }
}

module "policy" {
  source = "../../../modules/policy"

  management_group_id = data.terraform_remote_state.mg.outputs.prod_mg_id
  location            = var.location
  policy_mode         = var.policy_mode
  deny_public_ips     = var.deny_public_ips
}
