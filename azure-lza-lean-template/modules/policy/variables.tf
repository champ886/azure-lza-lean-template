# modules/policy/variables.tf
variable "management_group_id" {
  type = string
}
variable "location" {
  type = string
}
variable "policy_mode" {
  type    = string
  default = "audit"
}
variable "deny_public_ips" {
  type    = bool
  default = false
}
