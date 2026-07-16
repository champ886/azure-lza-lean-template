output "avnm_id"              { value = azurerm_network_manager.avnm.id }
output "dev_network_group_id" { value = azurerm_network_manager_network_group.dev_spokes.id }
output "prod_network_group_id"{ value = azurerm_network_manager_network_group.prod_spokes.id }
output "all_spokes_group_id"  { value = azurerm_network_manager_network_group.all_spokes.id }
