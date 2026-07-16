output "root_mg_id"         { value = azurerm_management_group.root.id }
output "platform_mg_id"     { value = azurerm_management_group.platform.id }
output "workloads_mg_id"    { value = azurerm_management_group.workloads.id }
output "nonprod_mg_id"      { value = azurerm_management_group.workload_nonprod.id }
output "prod_mg_id"         { value = azurerm_management_group.workload_prod.id }
