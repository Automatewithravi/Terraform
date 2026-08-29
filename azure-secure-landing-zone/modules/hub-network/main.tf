resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.env}"
  address_space       = ["10.10.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "bastion" {
  count                = var.deploy_bastion ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.0.0/26"]
}

resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "pip-bastion-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "this" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "bas-${var.env}"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}