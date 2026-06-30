output "product" {
  description = "Product deployed by this state."
  value       = var.product
}

output "resource_group_name" {
  description = "Resource group dedicated to this product."
  value       = azurerm_resource_group.product.name
}

output "storage_account_name" {
  description = "Storage account dedicated to this product."
  value       = azurerm_storage_account.product.name
}

output "queue_name" {
  description = "Queue dedicated to this product."
  value       = azurerm_storage_queue.product.name
}

