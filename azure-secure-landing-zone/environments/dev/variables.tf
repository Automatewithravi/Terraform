variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "deploy_bastion" {
  type    = bool
  default = false
}

variable "ssh_public_key" {
  type    = string
  default = "standard_B2s"
}

variable "hub_address_space" {
  type    = string
  default = "10.10.0.0/16"
  validation {
    condition     = can(cidrhost(var.hub_address_space, 0))
    error_message = "hub_address_space must be a valid CIDR block."
  }


}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}