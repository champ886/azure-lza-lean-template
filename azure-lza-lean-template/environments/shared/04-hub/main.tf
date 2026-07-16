# environments/shared/04-hub/main.tf
data "terraform_remote_state" "management" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/shared/03-management/terraform.tfstate"
  }
}

module "hub" {
  source = "../../../modules/hub"

  org_prefix             = var.org_prefix
  location               = var.location
  hub_address_space      = var.hub_address_space
  nva_subnet_cidr        = var.nva_subnet_cidr
  gateway_subnet_cidr    = var.gateway_subnet_cidr
  bastion_subnet_cidr    = var.bastion_subnet_cidr
  management_subnet_cidr = var.management_subnet_cidr
  nat_gw_subnet_cidr     = var.nat_gw_subnet_cidr
  router_vm_ip           = var.router_vm_ip
  router_ssh_public_key  = var.router_ssh_public_key
  law_workspace_id       = data.terraform_remote_state.management.outputs.law_workspace_id

  tags = {
    Environment = "shared"
    ManagedBy   = "Terraform"
    Layer       = "04-hub"
    OrgPrefix   = var.org_prefix
  }
}
