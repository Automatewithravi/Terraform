provider "azurerm" {
  features {}

  subscription_id = var.subscription_id

  # The pipeline identity only has rights on one resource group, so it cannot
  # register resource providers at subscription level.
  resource_provider_registrations = "none"

  # OIDC is switched on in the pipeline with ARM_USE_OIDC=true.
  # Locally, the same code works with `az login`.
}