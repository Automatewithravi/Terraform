# Replace the placeholder below with your own state storage account (see Step 0 of the guide).
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-landingzone"
    storage_account_name = "<your-state-storage-account>"
    container_name       = "tfstate-cicd"
    key                  = "cicd-identity-bootstrap.tfstate"
    use_azuread_auth     = true
  }
}
