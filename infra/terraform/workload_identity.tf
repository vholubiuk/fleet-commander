resource "azurerm_user_assigned_identity" "fleet" {
  name                = "id-fleet-commander"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}