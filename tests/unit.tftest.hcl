# Functional unit tests. Mocked Azure providers; no cloud credentials required.
# Requires Terraform >= 1.7 (`mock_provider`).

mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      name     = "rg-worklytics-import-test"
      location = "eastus"
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-worklytics-import-test"
    }
  }

  mock_data "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-worklytics-import-test/providers/Microsoft.Storage/storageAccounts/existingacct0001"
      name                  = "existingacct0001"
      primary_blob_endpoint = "https://existingacct0001.blob.core.windows.net/"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-worklytics-import-test/providers/Microsoft.Storage/storageAccounts/createdacct0001"
      name                  = "createdacct0001"
      primary_blob_endpoint = "https://createdacct0001.blob.core.windows.net/"
    }
  }

  mock_resource "azurerm_storage_container" {
    defaults = {
      name = "worklytics-import-container"
      id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-worklytics-import-test/providers/Microsoft.Storage/storageAccounts/createdacct0001/blobServices/default/containers/worklytics-import-container"
    }
  }

  mock_resource "azurerm_role_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000099"
    }
  }
}

mock_provider "azuread" {
  mock_resource "azuread_application" {
    defaults = {
      id        = "/applications/00000000-0000-0000-0000-000000000001"
      client_id = "00000000-0000-0000-0000-000000000001"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      id        = "00000000-0000-0000-0000-000000000002"
      object_id = "00000000-0000-0000-0000-000000000002"
      client_id = "00000000-0000-0000-0000-000000000001"
    }
  }

  mock_resource "azuread_application_federated_identity_credential" {
    defaults = {
      id            = "/applications/00000000-0000-0000-0000-000000000001/federatedIdentityCredentials/fic"
      credential_id = "fic"
    }
  }
}

variables {
  worklytics_tenant_id = "123456789012345678901"
  azure_tenant_id      = "11111111-1111-1111-1111-111111111111"
  resource_group_name  = "rg-worklytics-import-test"
  todos_as_local_files = false
}

run "creates_storage_when_omitted" {
  command = plan

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 1
    error_message = "Expected a storage account to be created when storage_account_name is omitted."
  }

  assert {
    condition     = length(azurerm_storage_container.worklytics) == 1
    error_message = "Expected a container to be created when storage_container_name is omitted."
  }

  assert {
    condition     = azurerm_role_assignment.role_contributor.role_definition_name == "Storage Blob Data Contributor"
    error_message = "Worklytics must be granted Storage Blob Data Contributor on the container."
  }

  assert {
    condition     = azurerm_role_assignment.role_delegator.role_definition_name == "Storage Blob Delegator"
    error_message = "Worklytics must be granted Storage Blob Delegator on the storage account."
  }

  assert {
    condition     = azuread_application_federated_identity_credential.worklytics.subject == var.worklytics_tenant_id
    error_message = "Federated credential subject must be the Worklytics tenant numeric ID."
  }

  assert {
    condition     = azuread_application_federated_identity_credential.worklytics.issuer == "https://accounts.google.com"
    error_message = "Federated credential issuer must be Google accounts."
  }
}

run "reuses_existing_storage_account" {
  command = plan

  variables {
    storage_account_name = "existingacct0001"
  }

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 0
    error_message = "Should not create a storage account when storage_account_name is provided."
  }

  assert {
    condition     = length(azurerm_storage_container.worklytics) == 1
    error_message = "Should still create a container when only the account is reused."
  }
}

run "reuses_existing_account_and_container" {
  command = plan

  variables {
    storage_account_name   = "existingacct0001"
    storage_container_name = "already-there"
  }

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 0
    error_message = "Should not create a storage account when one is provided."
  }

  assert {
    condition     = length(azurerm_storage_container.worklytics) == 0
    error_message = "Should not create a container when both account and container names are provided."
  }

  assert {
    condition     = output.storage_container_name == "already-there"
    error_message = "Output container name should match the provided existing container."
  }
}

run "rejects_non_numeric_tenant_id" {
  command = plan

  variables {
    worklytics_tenant_id = "not-a-numeric-id"
  }

  expect_failures = [
    var.worklytics_tenant_id,
  ]
}

run "rejects_short_tenant_id" {
  command = plan

  variables {
    worklytics_tenant_id = "1234567890"
  }

  expect_failures = [
    var.worklytics_tenant_id,
  ]
}

run "rejects_invalid_storage_account_name" {
  command = plan

  variables {
    storage_account_name = "NOT-VALID"
  }

  expect_failures = [
    var.storage_account_name,
  ]
}
