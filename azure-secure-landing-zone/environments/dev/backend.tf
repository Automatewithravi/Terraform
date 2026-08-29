terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-landingzone"
    storage_account_name = "sttflzstateh4dynn"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"

  }
}