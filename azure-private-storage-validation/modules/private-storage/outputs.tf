output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}
output "private_endpoint_ip" {
  value = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
  description = "private IP assigned to the blob endpoint inside snet-pe"
}

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.blob.id
}