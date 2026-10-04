resource "azurerm_virtual_network" "demo" {
  name                = "vnet-cicd-demo-${var.environment}"
  resource_group_name = data.azurerm_resource_group.target.name
  location            = data.azurerm_resource_group.target.location
  address_space       = ["10.60.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "demo" {
  name                 = "subnet-cicd-demo"
  resource_group_name  = data.azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = ["10.60.0.0/26"]
}
# Deny-by-default: no inbound rule is added, so nothing from outside
# the VNet can reach the VM. Verification uses az vm run-command
# (the Azure control plane), not a network path
resource "azurerm_network_security_group" "demo" {
  name                = "nsg-cicd-demo"
  resource_group_name = data.azurerm_resource_group.target.name
  location            = data.azurerm_resource_group.target.location
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "demo" {
  subnet_id                 = azurerm_subnet.demo.id
  network_security_group_id = azurerm_network_security_group.demo.id
}