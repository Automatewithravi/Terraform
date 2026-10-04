data "azurerm_resource_group" "target" {
  name = var.resource_group_name

}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  tags = {
    environment = var.environment
    managed_by  = "terraform"
    pipeline    = "github-actions-oidc"
    owner       = "ravi@automatewithravi.com"
    cost_centre = "portfolio"
  }
}

resource "azurerm_storage_account" "demo" {
  name                     = "stcicddemo${random_string.suffix.result}"
  resource_group_name      = data.azurerm_resource_group.target.name
  location                 = data.azurerm_resource_group.target.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.tags
}

