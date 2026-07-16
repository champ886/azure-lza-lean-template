# environments/dev/05-workload/variables.tf
variable "org_prefix"                   { type = string }
variable "environment"                  { type = string }
variable "location"                     { type = string }
variable "platform_subscription_id"     { type = string }
variable "workload_subscription_id"     { type = string }
variable "spoke_address_space"          { type = string }
variable "workload_subnet_cidr"         { type = string }
variable "aks_subnet_cidr"              { type = string }
variable "pe_subnet_cidr"              { type = string }
variable "acr_id"                       { type = string }
variable "flow_log_storage_account_id"  { type = string }
variable "tfstate_rg_name"             { type = string }
variable "tfstate_sa_name"             { type = string }
variable "tfstate_container"           { type = string }
