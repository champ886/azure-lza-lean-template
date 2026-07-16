# environments/shared/03-management/variables.tf
variable "org_prefix"               { type = string }
variable "org_name"                 { type = string }
variable "location"                 { type = string }
variable "platform_subscription_id" { type = string }
variable "security_email"           { type = string }
variable "law_retention_days"       { type = number }
variable "budget_amount"            { type = number }
variable "defender_tier"            { type = string }
variable "tfstate_rg_name"         { type = string }
variable "tfstate_sa_name"         { type = string }
variable "tfstate_container"       { type = string }
variable "management_subnet_id" {
  type        = string
  default     = ""
  description = "Hub management subnet ID for LAW private endpoint. Empty on first deploy — set after hub is deployed."
}
