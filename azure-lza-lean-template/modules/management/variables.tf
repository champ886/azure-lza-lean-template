# modules/management/variables.tf
variable "org_prefix" {
  type = string
}
variable "location" {
  type = string
}
variable "law_retention_days" {
  type    = number
  default = 30
}
variable "budget_amount" {
  type    = number
  default = 100
}
variable "defender_tier" {
  type    = string
  default = "Free"
}
variable "security_email" {
  type = string
}
variable "platform_subscription_id" {
  type = string
}
variable "management_subnet_id" {
  type    = string
  default = ""
}
variable "tags" {
  type    = map(string)
  default = {}
}
