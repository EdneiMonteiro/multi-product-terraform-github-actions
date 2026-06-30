variable "subscription_id" {
  description = "Azure subscription where the AKS platform cluster is deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group dedicated to the shared AKS platform."
  type        = string
  default     = "rg-platform-aks-poc"
}

variable "location" {
  description = "Azure region for the AKS platform."
  type        = string
  default     = "brazilsouth"
}

variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "aks-multiproduct-poc"
}

variable "kubernetes_version" {
  description = "Optional AKS Kubernetes version. Leave null to use the AKS default."
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_B2ms"
}

variable "tags" {
  description = "Tags applied to platform resources."
  type        = map(string)
  default = {
    poc        = "multi-product-terraform-github-actions"
    layer      = "platform"
    managed_by = "terraform"
  }
}
