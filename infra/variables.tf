variable "subscription_id" {
  description = "Azure subscription where product resources will be deployed."
  type        = string
}

variable "product" {
  description = "Product identifier used for naming, tagging, tfvars selection, and state isolation."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.product))
    error_message = "The product value must contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "poc"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.environment))
    error_message = "The environment value must contain only letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region for product resources."
  type        = string
  default     = "brazilsouth"
}

variable "resource_group_name" {
  description = "Resource group dedicated to this product deployment."
  type        = string
}

variable "tags" {
  description = "Extra tags applied to all supported resources."
  type        = map(string)
  default     = {}
}
