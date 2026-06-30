output "resource_group_name" {
  description = "Resource group of the AKS platform."
  value       = azurerm_resource_group.platform.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.platform.name
}

output "get_credentials_command" {
  description = "Command to fetch kubeconfig for the cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.platform.name} --name ${azurerm_kubernetes_cluster.platform.name}"
}
