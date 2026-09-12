resource "azurerm_resource_group" "main" {
  name = var.resource_group_name
  location = var.location
}
#Unique suffix so the storage account name is globally unique

resource "random_string" "suffix" {
  length = 6
  special = false
  upper = false
}

module "networking" {
  source = "./modules/networking"
  location = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags = local.common_tags
}

module "private_storage" {
  source = "./modules/private-storage"
  location = var.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_name = "stpriv${random_string.suffix.result}"
  spoke_vnet_id = module.networking.spoke_vnet_id
  pe_subnet_id = module.networking.pe-subnet_id
  tags = local.common_tags
}