variable "subscription_id" {
  type        = string
  description = "Target Azure subscription ID"
}

variable "resource_group_name" {
  type        = string
  description = "rg-cicd-demo-dev"
}

variable "environment" {
  type    = string
  default = "dev"
}
variable "vm_size" {
  type        = string
  default     = "Standard_B1s"
  description = "Smallest general-purpose burstable size; enough to prove the pipeline works"
}

variable "admin_username" {
  type        = string
  description = "azureadmin"
}
variable "admin_ssh_public_key" {
  type        = string
  description = "SSH PUBLIC key only (from Step 5a1). Never generate or store the private key in Terraform, state, or the repo."
}

