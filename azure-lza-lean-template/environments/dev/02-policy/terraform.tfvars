# environments/dev/02-policy/terraform.tfvars
location                = "australiaeast"
platform_subscription_id = "YOUR_PLATFORM_SUBSCRIPTION_ID"
policy_mode             = "audit"
deny_public_ips         = false
tfstate_rg_name        = "YOUR_ORG_PREFIX-tfstate-platform"
tfstate_sa_name         = "YOUR_TFSTATE_SA_NAME"
tfstate_container      = "tfstate"
