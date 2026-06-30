locals {
  normalized_product     = lower(replace(var.product, "-", ""))
  normalized_environment = lower(replace(var.environment, "-", ""))

  common_tags = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
      poc         = "multi-product-terraform-github-actions"
      product     = var.product
    },
    var.tags
  )
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  numeric = true
  special = false
  upper   = false
}

resource "azurerm_resource_group" "product" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "product" {
  name                            = substr("st${local.normalized_product}${local.normalized_environment}${random_string.suffix.result}", 0, 24)
  resource_group_name             = azurerm_resource_group.product.name
  location                        = azurerm_resource_group.product.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.common_tags
}

resource "azurerm_storage_container" "product" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.product.id
  container_access_type = "private"
}

resource "azurerm_storage_queue" "product" {
  name                 = "${lower(var.product)}-${lower(var.environment)}-events"
  storage_account_name = azurerm_storage_account.product.name
}

