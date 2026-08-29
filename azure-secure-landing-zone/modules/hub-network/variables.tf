variable "env" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "deploy_bastion" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}