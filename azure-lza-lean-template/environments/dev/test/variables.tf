variable "location" {
  type    = string
  default = "australiaeast"
}
variable "vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
variable "workload_subscription_id" {
  type    = string
  default = "YOUR_NONPROD_SUBSCRIPTION_ID"
}
