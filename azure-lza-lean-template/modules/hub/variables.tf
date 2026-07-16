# modules/hub/variables.tf
variable "org_prefix" {
  type = string
}
variable "location" {
  type = string
}
variable "hub_address_space" {
  type    = string
  default = "10.2.0.0/16"
}
variable "nva_subnet_cidr" {
  type    = string
  default = "10.2.1.0/24"
}
variable "gateway_subnet_cidr" {
  type    = string
  default = "10.2.0.64/27"
}
variable "bastion_subnet_cidr" {
  type    = string
  default = "10.2.0.128/27"
}
variable "management_subnet_cidr" {
  type    = string
  default = "10.2.2.0/24"
}
variable "nat_gw_subnet_cidr" {
  type    = string
  default = "10.2.3.0/24"
}
variable "router_vm_ip" {
  type    = string
  default = "10.2.1.4"
}
variable "router_ssh_public_key" {
  type      = string
  sensitive = true
}
variable "law_workspace_id" {
  type = string
}
variable "enable_ip_forwarding" {
  type    = bool
  default = true
}
variable "enable_accelerated_networking" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
