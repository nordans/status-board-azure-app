moved {
  from = azurerm_virtual_network.platform
  to   = module.network.azurerm_virtual_network.platform
}

moved {
  from = azurerm_subnet.nodes
  to   = module.network.azurerm_subnet.nodes
}

moved {
  from = azurerm_container_registry.app
  to   = module.registry.azurerm_container_registry.app
}

moved {
  from = azurerm_key_vault.app
  to   = module.key_vault.azurerm_key_vault.app
}

moved {
  from = azurerm_user_assigned_identity.cluster
  to   = module.aks.azurerm_user_assigned_identity.cluster
}

moved {
  from = azurerm_role_assignment.cluster_network
  to   = module.aks.azurerm_role_assignment.cluster_network
}

moved {
  from = azurerm_user_assigned_identity.kubelet
  to   = module.aks.azurerm_user_assigned_identity.kubelet
}

moved {
  from = azurerm_role_assignment.cluster_kubelet
  to   = module.aks.azurerm_role_assignment.cluster_kubelet
}

moved {
  from = azurerm_role_assignment.image_pull
  to   = module.aks.azurerm_role_assignment.image_pull
}

moved {
  from = azurerm_kubernetes_cluster.platform
  to   = module.aks.azurerm_kubernetes_cluster.platform
}

moved {
  from = azurerm_user_assigned_identity.app
  to   = module.workload_identity.azurerm_user_assigned_identity.app
}

moved {
  from = azurerm_federated_identity_credential.app
  to   = module.workload_identity.azurerm_federated_identity_credential.app
}

moved {
  from = azurerm_role_assignment.app_secrets
  to   = module.workload_identity.azurerm_role_assignment.app_secrets
}
