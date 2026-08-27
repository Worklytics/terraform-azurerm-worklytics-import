terraform {
  required_version = ">= 1.3, < 2.0"

  required_providers {
    # Azure Resource Manager: storage account, blob container, RBAC role assignments.
    # >= 4.0 required for storage_account_id on azurerm_storage_container (RM API).
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    # Entra ID: app registration, service principal, federated identity credential.
    # Separate HashiCorp provider; azurerm does not cover these resources.
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}
