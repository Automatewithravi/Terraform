output "storage_account_name" {
  value = module.private_storage.storage_account_name
}
output "private_endpoint_ip" {
  value = module.private_storage.private_endpoint_ip
}

output "spoke_vnet_name" {
  value = module.networking.spoke_vnet_name
}