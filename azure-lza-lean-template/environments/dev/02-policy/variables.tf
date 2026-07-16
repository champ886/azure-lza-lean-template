# environments/dev/02-policy/variables.tf
variable "location"                 { type = string }
variable "platform_subscription_id" { type = string }
variable "policy_mode"              { type = string }
variable "deny_public_ips"          { type = bool }
variable "tfstate_rg_name"         { type = string }
variable "tfstate_sa_name"         { type = string }
variable "tfstate_container"       { type = string }
