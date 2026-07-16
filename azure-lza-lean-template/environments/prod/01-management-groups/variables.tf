# environments/prod/01-management-groups/variables.tf
variable "platform_subscription_id" { type = string }
variable "tfstate_rg_name"         { type = string }
variable "tfstate_sa_name"         { type = string }
variable "tfstate_container"       { type = string }
