variable "subscription_id" {
  type        = string
  description = "Target Azure subscription ID"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "github_owner" {
  type        = string
  description = "GitHub user or organisation that owns the repository"
}

variable "github_repo" {
  type        = string
  description = "Name of the GitHub repository (without the owner)"
}

variable "github_environment" {
  type        = string
  default     = "dev-apply"
  description = "GitHub environment whose approval gate protects apply"
}

variable "state_storage_account" {
  type        = string
  description = "Existing storage account that holds the Terraform state"
}

variable "state_resource_group" {
  type    = string
  default = "rg-tfstate-landingzone"
}

variable "state_container" {
  type    = string
  default = "tfstate-cicd"
}

variable "target_resource_group_name" {
  type    = string
  default = "rg-cicd-demo-dev"
}

variable "ado_issuer" {
  type    = string
  default = null
}

variable "ado_subject_plan" {
  type    = string
  default = null
}

variable "ado_subject_apply" {
  type    = string
  default = null
}