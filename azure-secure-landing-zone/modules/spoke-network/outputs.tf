output "vnet_name" {
  value = azurerm_virtual_network.spoke.name
}

output "vnet_id" {
  value = azurerm_virtual_network.spoke.id
}

output "workload_subnet_id" {
  value = azurerm_subnet.workload.id
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}