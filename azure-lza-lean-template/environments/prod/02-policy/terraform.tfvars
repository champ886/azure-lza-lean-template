# environments/prod/02-policy/terraform.tfvars
location                 = "australiaeast"
platform_subscription_id = "YOUR_PLATFORM_SUBSCRIPTION_ID"
policy_mode              = "enforce"   # prod: Deny + DINE
deny_public_ips          = true        # blocks public IP creation on NICs
tfstate_rg_name         = "YOUR_ORG_PREFIX-tfstate-platform"
tfstate_sa_name         = "YOUR_TFSTATE_SA_NAME"
tfstate_container       = "tfstate"
