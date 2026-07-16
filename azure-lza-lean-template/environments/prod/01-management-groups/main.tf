# environments/prod/01-management-groups/main.tf
# MG hierarchy created once in dev/01-management-groups
# This layer reads that state and outputs prod MG ID for prod/02-policy
data "terraform_remote_state" "mg" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/dev/01-management-groups/terraform.tfstate"
  }
}
output "root_mg_id" { value = data.terraform_remote_state.mg.outputs.root_mg_id }
output "prod_mg_id" { value = data.terraform_remote_state.mg.outputs.prod_mg_id }
