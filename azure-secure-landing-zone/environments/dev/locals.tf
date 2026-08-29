locals {
  env    = "dev"
  prefix = "lz"
  common_tags = {

    project     = "secure-landing-zone"
    environment = local.env
    location    = var.location
    managed_by  = "terraform"
  }
}