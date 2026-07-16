# environments/shared/04-hub/variables.tf
variable "org_prefix" {
  type = string
}
variable "location" {
  type = string
}
variable "platform_subscription_id" {
  type = string
}
variable "hub_address_space" {
  type = string
}
variable "nva_subnet_cidr" {
  type = string
}
variable "gateway_subnet_cidr" {
  type = string
}
variable "bastion_subnet_cidr" {
  type = string
}
variable "management_subnet_cidr" {
  type = string
}
variable "nat_gw_subnet_cidr" {
  type = string
}
variable "router_vm_ip" {
  type = string
}
variable "router_ssh_public_key" {
  type      = string
  sensitive = true
}
variable "tfstate_rg_name" {
  type = string
}
variable "tfstate_sa_name" {
  type = string
}
variable "tfstate_container" {
  type = string
}
