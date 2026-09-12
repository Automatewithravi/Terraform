#Hub vnet
resource "azurerm_virtual_network" "hub" {
  name = "vnet-hub"
  location = var.location
  resource_group_name = var.resource_group_name
  address_space = ["10.10.0.0/16"]
  tags = var.tags
}

# Spoke vnet
resource "azurerm_virtual_network" "spoke" {
  name = "vnet-spoke"
  location = var.location
  resource_group_name = var.resource_group_name
  address_space = ["10.20.0.0/16"]
  tags = var.tags
}

# Spoke subnet: private endpoints
resource "azurerm_subnet" "pe" {
  name = "snet-pe"
  resource_group_name = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes = ["10.20.2.0/24"]
  private_endpoint_network_policies = "Disabled"
}

# Bidirectional peering: hub <-> spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name = "peer-hub-to-spoke"
  resource_group_name = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic = true
  allow_virtual_network_access = true
  }

  resource "azurerm_virtual_network_peering" "spoke-to-hub" {
  name = "peer-spoke-to-hub"
  resource_group_name = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_forwarded_traffic = true
  allow_virtual_network_access = true
  }
  # NSG on the PE subnet (deny-by-default inbound from internet, allow intra-VNet)
resource "azurerm_network_security_group" "pe" {
  name                = "nsg-snet-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}