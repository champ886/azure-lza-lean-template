# modules/workload/variables.tf
variable "environment" {
  type = string
}
variable "org_prefix" {
  type = string
}
variable "location" {
  type = string
}
variable "tenant_id" {
  type = string
}
variable "spoke_address_space" {
  type = string
}
variable "workload_subnet_cidr" {
  type = string
}
variable "aks_subnet_cidr" {
  type = string
}
variable "pe_subnet_cidr" {
  type = string
}
variable "law_workspace_id" {
  type = string
}
variable "law_workspace_guid" {
  type = string
}
variable "management_rg_name" {
  type = string
}
variable "dns_zone_blob_id" {
  type = string
}
variable "dns_zone_vault_id" {
  type = string
}
variable "dns_zone_acr_id" {
  type = string
}
variable "dns_zone_monitor_id" {
  type = string
}
variable "dns_zone_blob_name" {
  type = string
}
variable "dns_zone_vault_name" {
  type = string
}
variable "dns_zone_acr_name" {
  type = string
}
variable "dns_zone_monitor_name" {
  type = string
}
variable "acr_id" {
  type    = string
  default = ""
}
variable "storage_account_id" {
  type    = string
  default = ""
}
variable "flow_log_storage_account_id" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
