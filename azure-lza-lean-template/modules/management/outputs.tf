# modules/management/outputs.tf
output "law_workspace_id" {
  value = azurerm_log_analytics_workspace.law.id
}
output "law_workspace_key" {
  value     = azurerm_log_analytics_workspace.law.primary_shared_key
  sensitive = true
}
output "management_rg_name" {
  value = azurerm_resource_group.management.name
}
output "dns_zone_blob_id" {
  value = azurerm_private_dns_zone.blob.id
}
output "dns_zone_vault_id" {
  value = azurerm_private_dns_zone.vault.id
}
output "dns_zone_acr_id" {
  value = azurerm_private_dns_zone.acr.id
}
output "dns_zone_aks_id" {
  value = azurerm_private_dns_zone.aks.id
}
output "dns_zone_monitor_id" {
  value = azurerm_private_dns_zone.monitor.id
}
output "dns_zone_blob_name" {
  value = azurerm_private_dns_zone.blob.name
}
output "dns_zone_vault_name" {
  value = azurerm_private_dns_zone.vault.name
}
output "dns_zone_acr_name" {
  value = azurerm_private_dns_zone.acr.name
}
output "dns_zone_monitor_name" {
  value = azurerm_private_dns_zone.monitor.name
}
output "management_rg_id" {
  value = azurerm_resource_group.management.id
}
output "management_subnet_id" {
  value = ""
  description = "Placeholder — management subnet lives in hub module"
}
