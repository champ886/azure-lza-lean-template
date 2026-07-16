# environments/shared/05-avnm/terraform.tfvars
org_prefix               = "YOUR_ORG_PREFIX"
location                 = "australiaeast"
platform_subscription_id = "YOUR_PLATFORM_SUBSCRIPTION_ID"
nonprod_subscription_id  = "YOUR_NONPROD_SUBSCRIPTION_ID"
prod_subscription_id     = "YOUR_PROD_SUBSCRIPTION_ID"
tfstate_rg_name         = "YOUR_ORG_PREFIX-tfstate-platform"
tfstate_sa_name         = "YOUR_TFSTATE_SA_NAME"
tfstate_container       = "tfstate"

# Phase 1: leave empty — uses router VM IP from hub state output
# Phase 2: set to ILB frontend IP (e.g. "10.2.1.5") to graduate to OPNsense
nva_next_hop_ip_override = ""
