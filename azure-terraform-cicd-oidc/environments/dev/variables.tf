variable "subscription_id" {
  type        = string
  description = "Target Azure subscription ID"
}

variable "resource_group_name" {
  type    = string
  default = "rg-cicd-demo-dev"
}

variable "environment" {
  type    = string
  default = "dev"
}
variable "vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "VM size (SKU)."
}

variable "admin_username" {
  type    = string
  default = "azureadmin"
}
variable "admin_ssh_public_key" {
  type        = string
  description = "SSH PUBLIC key only (from Step 5a1). Never generate or store the private key in Terraform, state, or the repo."
}

