# environments/shared/03-management/terraform.tfvars
org_prefix               = "YOUR_ORG_PREFIX"
org_name                 = "YOUR_ORG_NAME"
location                 = "australiaeast"
platform_subscription_id = "YOUR_PLATFORM_SUBSCRIPTION_ID"
security_email           = "YOUR_SECURITY_EMAIL"
law_retention_days       = 90
budget_amount            = 500
defender_tier            = "Standard"
tfstate_rg_name         = "YOUR_ORG_PREFIX-tfstate-platform"
tfstate_sa_name         = "YOUR_TFSTATE_SA_NAME"
tfstate_container       = "tfstate"

# Leave empty on first deploy — fill in after shared/04-hub is applied
# Get value with: terraform output -state=environments/shared/04-hub/terraform.tfstate management_subnet_id
management_subnet_id = ""
