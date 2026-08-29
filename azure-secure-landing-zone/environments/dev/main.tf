module "resource_group" {
  source   = "../../modules/resource-group"
  name     = "rg-landingzone-${local.env}"
  location = var.location
  tags     = local.common_tags
}

module "hub_network" {
  source              = "../../modules/hub-network"
  env                 = local.env
  location            = var.location
  resource_group_name = module.resource_group.name
  deploy_bastion      = var.deploy_bastion
  tags                = local.common_tags
}

module "spoke_network" {
  source              = "../../modules/spoke-network"
  env                 = local.env
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = module.resource_group.name
  virtual_network_name      = module.hub_network.vnet_name
  remote_virtual_network_id = module.spoke_network.vnet_id
  allow_forwarded_traffic   = false
  allow_gateway_transit     = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = module.resource_group.name
  virtual_network_name      = module.spoke_network.vnet_name
  remote_virtual_network_id = module.hub_network.vnet_id
  allow_forwarded_traffic   = false
  use_remote_gateways       = false
}

module "virtual_machine" {
  source              = "../../modules/virtual-machine"
  env                 = local.env
  location            = var.location
  resource_group_name = module.resource_group.name
  subnet_id           = module.spoke_network.workload_subnet_id
  vm_size             = var.vm_size
  admin_username      = "azureadmin"
  ssh_public_key      = var.ssh_public_key
}
