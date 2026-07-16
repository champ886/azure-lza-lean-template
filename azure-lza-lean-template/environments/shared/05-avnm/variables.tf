# environments/shared/05-avnm/variables.tf
variable "org_prefix"                { type = string }
variable "location"                  { type = string }
variable "platform_subscription_id"  { type = string }
variable "nonprod_subscription_id"   { type = string }
variable "prod_subscription_id"      { type = string }
variable "tfstate_rg_name"          { type = string }
variable "tfstate_sa_name"          { type = string }
variable "tfstate_container"        { type = string }
# Phase 1: router VM IP (10.2.1.4)
# Phase 2: change to ILB frontend IP — AVNM propagates to all spokes automatically
variable "nva_next_hop_ip_override" {
  type        = string
  default     = ""
  description = "Leave empty to use router_vm_ip from hub state. Set to ILB frontend IP for Phase 2."
}
