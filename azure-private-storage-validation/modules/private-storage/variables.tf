variable "resource_group_name" {
  type        = string
  default = "rg-private-storage-validation"
  description = "Resource group for storage + private endpoint"
}

variable "location" {
  type        = string
  default     = "centralindia"
  description = "Azure region"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name (lowercase, no hyphens, 3-24 chars)"
}

variable "spoke_vnet_id" {
  type        = string
  description = "Spoke VNet resource ID for the private DNS zone link"
}

variable "pe_subnet_id" {
  type        = string
  description = "snet-pe subnet resource ID where the private endpoint NIC is placed"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common resource tags"
}