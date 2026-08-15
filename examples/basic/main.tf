# Development / CI example only. Customers should copy from the root README or
# examples/basic-remote/ (Terraform Registry source), not this relative path.

terraform {
  # Local state is convenient for iterating on this repo and for GitHub Actions e2e.
  # Do NOT use a local backend in production; use remote state (Terraform Cloud, azurerm,
  # GCS, S3, etc.) so state is shared, locked, and backed up.
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    # Storage accounts, blob containers, and Azure RBAC (role assignments).
    # Floor 4.0: containers are managed via storage_account_id (Resource Manager API).
    # 3.x used storage_account_name / data-plane APIs, which 4.x deprecated.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    # Entra ID (Azure AD): application, service principal, and federated identity
    # credential (Google → Entra WIF). HashiCorp splits this from azurerm; both are
    # required. There is no azurerm resource for federated identity credentials.
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47"
    }
  }
}

# In real use you likely already have these provider blocks in the root module.
provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
}

provider "azuread" {
  tenant_id = var.azure_tenant_id
}

module "worklytics_import" {
  # Relative source so CI tests *this* checkout. Published usage:
  #   source  = "Worklytics/worklytics-import/azure"
  #   version = "~> 0.1.0"
  source = "../../"

  resource_name_prefix       = var.resource_name_prefix
  worklytics_tenant_id       = var.worklytics_tenant_id
  worklytics_tenant_sa_email = var.worklytics_tenant_sa_email
  azure_tenant_id            = var.azure_tenant_id
  resource_group_name        = var.resource_group_name
  location                   = var.location
  storage_account_name       = var.storage_account_name
  storage_container_name     = var.storage_container_name
  import_containers          = var.import_containers
  owners                     = var.owners
  todos_as_local_files       = var.todos_as_local_files
}

output "storage_account_name" {
  value = module.worklytics_import.storage_account_name
}

output "storage_container_name" {
  value = module.worklytics_import.storage_container_name
}

output "import_containers" {
  value = module.worklytics_import.import_containers
}

output "application_client_id" {
  value = module.worklytics_import.application_client_id
}

output "service_principal_object_id" {
  value = module.worklytics_import.service_principal_object_id
}
