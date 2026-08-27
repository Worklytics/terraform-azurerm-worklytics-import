# Default provider pins for this example. GitHub Actions overwrites this file
# during the azurerm 4.x/5.x compatibility matrix (same filename) so there is
# only one required_providers block in the example module.
#
# Storage accounts, blob containers, and Azure RBAC (role assignments).
# Floor 4.0: containers are managed via storage_account_id (Resource Manager API).
# 3.x used storage_account_name / data-plane APIs, which 4.x deprecated.
#
# azuread: Entra ID application, service principal, and federated identity
# credential (Google → Entra WIF). HashiCorp splits this from azurerm; both are
# required. There is no azurerm resource for federated identity credentials.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47"
    }
  }
}
