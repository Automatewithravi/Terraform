resource "azurerm_network_interface" "demo" {
  name                = "nic-cicd-demo-vm"
  resource_group_name = data.azurerm_resource_group.target.name
  location            = data.azurerm_resource_group.target.location
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.demo.id
    private_ip_address_allocation = "Dynamic"
  }


}

resource "azurerm_linux_virtual_machine" "demo" {
  name                  = "vm-cicd-demo-01"
  resource_group_name   = data.azurerm_resource_group.target.name
  location              = data.azurerm_resource_group.target.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.demo.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  tags = local.tags
}