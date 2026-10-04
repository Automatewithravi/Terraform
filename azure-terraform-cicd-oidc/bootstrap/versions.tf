terraform {
  required_version = "~>1.15.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.1"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

