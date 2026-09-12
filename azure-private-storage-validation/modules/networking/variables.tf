variable "location" {
  type = string
  default = "centralindia"
  description = "Azure region"
}

variable "resource_group_name" {
  type = string
  default = "rg-private-storage-validation"
  description = "Resource group for all networking resources"
}

variable "tags" {
  type = map(string)
  default = {}  
  description = "Common resource tags"
}

