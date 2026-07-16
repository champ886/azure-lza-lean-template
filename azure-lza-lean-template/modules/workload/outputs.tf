output "spoke_vnet_id"        { value = azurerm_virtual_network.spoke.id }
output "spoke_vnet_name"      { value = azurerm_virtual_network.spoke.name }
output "workload_subnet_id"   { value = azurerm_subnet.workload.id }
output "aks_subnet_id"        { value = azurerm_subnet.aks.id }
output "pe_subnet_id"         { value = azurerm_subnet.pe.id }
output "workload_rg_name"     { value = azurerm_resource_group.workload.name }
output "key_vault_id"         { value = azurerm_key_vault.spoke.id }
output "key_vault_uri"        { value = azurerm_key_vault.spoke.vault_uri }
