# modules/avnm/variables.tf
variable "org_prefix" {
  type = string
}
variable "location" {
  type = string
}
variable "hub_rg_name" {
  type = string
}
variable "hub_vnet_id" {
  type = string
}
variable "platform_subscription_id" {
  type = string
}
variable "nonprod_subscription_id" {
  type = string
}
variable "prod_subscription_id" {
  type = string
}
variable "dev_spoke_vnet_ids" {
  type    = list(string)
  default = []
}
variable "prod_spoke_vnet_ids" {
  type    = list(string)
  default = []
}
variable "nva_next_hop_ip" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
