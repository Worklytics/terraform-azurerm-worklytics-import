# Development / CI example only. Customers should copy from the root README or
# examples/basic-remote/ (Terraform Registry source), not this relative path.

terraform {
  # Local state is convenient for iterating on this repo and for GitHub Actions e2e.
  # Do NOT use a local backend in production; use remote state (Terraform Cloud, azurerm,
  # GCS, S3, etc.) so state is shared, locked, and backed up.
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Provider version constraints live in azurerm_provider_version_test.tf so the
# integration workflow can overwrite that file to pin azurerm majors. A second
# required_providers block here would fail terraform init.

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
