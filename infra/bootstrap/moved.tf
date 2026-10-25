moved {
  from = azurerm_storage_account.state
  to   = module.state_backend.azurerm_storage_account.state
}

moved {
  from = azurerm_storage_container.state
  to   = module.state_backend.azurerm_storage_container.state
}
