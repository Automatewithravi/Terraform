output "storage_account_name" {
  value = azurerm_storage_account.demo.name
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.demo.name
}

output "vm_private_ip" {
  value = azurerm_network_interface.demo.private_ip_address
}
