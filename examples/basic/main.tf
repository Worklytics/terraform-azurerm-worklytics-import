# basic example of using this module; really as much for dev/testing as a real example of practical
# usage

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 6"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47"
    }
  }
}

# provider just for example purposes; in real use, you likely already have azurerm/azuread
# provider blocks in your terraform configuration
provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
}

provider "azuread" {
  tenant_id = var.azure_tenant_id
}

module "worklytics_import" {
  source = "../../"

  resource_name_prefix       = var.resource_name_prefix
  worklytics_tenant_id       = var.worklytics_tenant_id
  worklytics_tenant_sa_email = var.worklytics_tenant_sa_email
  azure_tenant_id            = var.azure_tenant_id
  resource_group_name        = var.resource_group_name
  location                   = var.location
  storage_account_name       = var.storage_account_name
  storage_container_name     = var.storage_container_name
  owners                     = var.owners
  todos_as_local_files       = var.todos_as_local_files
}

output "storage_account_name" {
  value = module.worklytics_import.storage_account_name
}

output "storage_container_name" {
  value = module.worklytics_import.storage_container_name
}

output "application_client_id" {
  value = module.worklytics_import.application_client_id
}

output "service_principal_object_id" {
  value = module.worklytics_import.service_principal_object_id
}
