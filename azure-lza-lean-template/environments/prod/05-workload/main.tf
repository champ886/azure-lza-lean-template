# environments/prod/05-workload/main.tf
# NO peering resources — AVNM owns peerings
# NO UDR resources — AVNM routing config pushes default route to this spoke

data "azurerm_client_config" "current" {}

data "terraform_remote_state" "management" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_rg_name
    storage_account_name = var.tfstate_sa_name
    container_name       = var.tfstate_container
    key                  = "alz/shared/03-management/terraform.tfstate"
  }
}

module "workload" {
  source = "../../../modules/workload"

  environment          = var.environment
  org_prefix           = var.org_prefix
  location             = var.location
  tenant_id            = data.azurerm_client_config.current.tenant_id
  spoke_address_space  = var.spoke_address_space
  workload_subnet_cidr = var.workload_subnet_cidr
  aks_subnet_cidr      = var.aks_subnet_cidr
  pe_subnet_cidr       = var.pe_subnet_cidr
  acr_id               = var.acr_id

  law_workspace_id            = data.terraform_remote_state.management.outputs.law_workspace_id
  law_workspace_guid          = data.terraform_remote_state.management.outputs.law_workspace_id
  management_rg_name          = data.terraform_remote_state.management.outputs.management_rg_name
  dns_zone_blob_id            = data.terraform_remote_state.management.outputs.dns_zone_blob_id
  dns_zone_vault_id           = data.terraform_remote_state.management.outputs.dns_zone_vault_id
  dns_zone_acr_id             = data.terraform_remote_state.management.outputs.dns_zone_acr_id
  dns_zone_monitor_id         = data.terraform_remote_state.management.outputs.dns_zone_monitor_id
  dns_zone_blob_name          = data.terraform_remote_state.management.outputs.dns_zone_blob_name
  dns_zone_vault_name         = data.terraform_remote_state.management.outputs.dns_zone_vault_name
  dns_zone_acr_name           = data.terraform_remote_state.management.outputs.dns_zone_acr_name
  dns_zone_monitor_name       = data.terraform_remote_state.management.outputs.dns_zone_monitor_name
  flow_log_storage_account_id = var.flow_log_storage_account_id

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Layer       = "05-workload"
    OrgPrefix   = var.org_prefix
  }
}

output "spoke_vnet_id" { value = module.workload.spoke_vnet_id }
output "key_vault_id"  { value = module.workload.key_vault_id }
