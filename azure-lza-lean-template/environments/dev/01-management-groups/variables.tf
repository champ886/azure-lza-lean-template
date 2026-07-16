# environments/dev/01-management-groups/variables.tf
variable "org_prefix"               { type = string }
variable "org_name"                 { type = string }
variable "platform_subscription_id" { type = string }
variable "nonprod_subscription_id"  { type = string }
variable "prod_subscription_id"     { type = string }
