output "tenant_id" {
  value = azurerm_user_assigned_identity.plan.tenant_id
}

output "plan_client_id" {
  value = azurerm_user_assigned_identity.plan.client_id
}

output "apply_client_id" {
  value = azurerm_user_assigned_identity.apply.client_id
}

output "target_resource_group" {
  value = azurerm_resource_group.target.name
}