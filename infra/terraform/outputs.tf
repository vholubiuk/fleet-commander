output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "key_vault_name" {
  value = azurerm_key_vault.fleet.name
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "fleet_identity_client_id" {
  value = azurerm_user_assigned_identity.fleet.client_id
}