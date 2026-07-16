# environments/shared/05-avnm/main.tf
# Runs after dev AND prod workload spokes exist in state
# nva_next_hop_ip_override: "" = use router VM IP (Phase 1)
#                           "10.2.1.5" = ILB frontend (Phase 2)

data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/shared/04-hub/terraform.tfstate"
  }
}

data "terraform_remote_state" "dev_workload" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/dev/05-workload/terraform.tfstate"
  }
}

data "terraform_remote_state" "prod_workload" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/prod/05-workload/terraform.tfstate"
  }
}

locals {
  # Use override if set, otherwise fall back to router VM IP from hub state
  nva_next_hop_ip = var.nva_next_hop_ip_override != "" ? var.nva_next_hop_ip_override : data.terraform_remote_state.hub.outputs.router_vm_ip
}

module "avnm" {
  source = "../../../modules/avnm"

  org_prefix               = var.org_prefix
  location                 = var.location
  hub_rg_name              = data.terraform_remote_state.hub.outputs.hub_rg_name
  hub_vnet_id              = data.terraform_remote_state.hub.outputs.hub_vnet_id
  platform_subscription_id = var.platform_subscription_id
  nonprod_subscription_id  = var.nonprod_subscription_id
  prod_subscription_id     = var.prod_subscription_id
  dev_spoke_vnet_ids       = [data.terraform_remote_state.dev_workload.outputs.spoke_vnet_id]
  prod_spoke_vnet_ids      = [data.terraform_remote_state.prod_workload.outputs.spoke_vnet_id]
  nva_next_hop_ip          = local.nva_next_hop_ip

  tags = {
    Environment = "shared"
    ManagedBy   = "Terraform"
    Layer       = "05-avnm"
  }
}
