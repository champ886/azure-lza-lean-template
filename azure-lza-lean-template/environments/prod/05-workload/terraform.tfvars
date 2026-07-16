# environments/prod/05-workload/terraform.tfvars
org_prefix               = "YOUR_ORG_PREFIX"
environment              = "prod"
location                 = "australiaeast"
platform_subscription_id = "YOUR_PLATFORM_SUBSCRIPTION_ID"
workload_subscription_id = "YOUR_PROD_SUBSCRIPTION_ID"
spoke_address_space      = "10.20.0.0/16"
workload_subnet_cidr     = "10.20.1.0/24"
aks_subnet_cidr          = "10.20.2.0/22"
pe_subnet_cidr           = "10.20.10.0/24"
acr_id                   = ""   # set when ACR is created
tfstate_rg_name         = "YOUR_ORG_PREFIX-tfstate-platform"
tfstate_sa_name         = "YOUR_TFSTATE_SA_NAME"
tfstate_container       = "tfstate"
# flow_log_storage_account_id — set in local.tfvars (gitignored)
