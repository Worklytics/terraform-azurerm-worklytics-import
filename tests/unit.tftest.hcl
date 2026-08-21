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
      # azuread 3.x resource id vs object GUID — RBAC must use object_id.
      id        = "/servicePrincipals/00000000-0000-0000-0000-000000000002"
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
    error_message = "Expected a storage account to be created when import_containers omits account names."
  }

  assert {
    condition     = azurerm_storage_account.worklytics[0].infrastructure_encryption_enabled == true
    error_message = "Created storage accounts should enable infrastructure encryption."
  }

  assert {
    condition     = length(azurerm_storage_container.import) == 1
    error_message = "Expected a container to be created when import_containers omits container names."
  }

  assert {
    condition = alltrue([
      for ra in azurerm_role_assignment.import_contributor :
      ra.role_definition_name == "Storage Blob Data Contributor"
    ])
    error_message = "Worklytics must be granted Storage Blob Data Contributor on the container."
  }

  assert {
    condition = alltrue([
      for ra in azurerm_role_assignment.import_delegator :
      ra.role_definition_name == "Storage Blob Delegator"
    ])
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
    import_containers = [
      {
        storage_account_name = "existingacct0001"
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 0
    error_message = "Should not create a storage account when storage_account_name is provided."
  }

  assert {
    condition     = length(azurerm_storage_container.import) == 1
    error_message = "Should still create a container when only the account is reused."
  }
}

run "reuses_existing_account_and_container" {
  command = plan

  variables {
    import_containers = [
      {
        storage_account_name   = "existingacct0001"
        storage_container_name = "already-there"
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 0
    error_message = "Should not create a storage account when one is provided."
  }

  assert {
    condition     = length(azurerm_storage_container.import) == 0
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
    import_containers = [
      {
        storage_account_name = "NOT-VALID"
      }
    ]
  }

  expect_failures = [
    var.import_containers,
  ]
}

run "rejects_empty_import_containers" {
  command = plan

  variables {
    import_containers = []
  }

  expect_failures = [
    var.import_containers,
  ]
}

run "grants_access_to_additional_import_containers" {
  command = plan

  variables {
    import_containers = [
      {
        storage_account_name   = "existingacct0001"
        storage_container_name = "already-there"
      },
      {
        storage_account_name   = "existingacct0001"
        storage_container_name = "second-ingest"
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 0
    error_message = "Should not create a storage account when all import locations already exist."
  }

  assert {
    condition     = length(azurerm_storage_container.import) == 0
    error_message = "Should not create containers when all import locations already exist."
  }

  assert {
    condition     = length(azurerm_role_assignment.import_contributor) == 2
    error_message = "Each import container should get Contributor."
  }

  assert {
    condition     = length(output.import_containers) == 2
    error_message = "import_containers output should include every listed container."
  }
}

run "list_only_skips_created_storage" {
  command = plan

  variables {
    import_containers = [
      {
        storage_account_name   = "existingacct0001"
        storage_container_name = "only-from-list"
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_account.worklytics) == 0
    error_message = "Existing listed locations should not create a storage account."
  }

  assert {
    condition     = length(azurerm_role_assignment.import_contributor) == 1
    error_message = "Should grant access to exactly the listed containers."
  }

  assert {
    condition     = output.storage_container_name == "only-from-list"
    error_message = "Convenience outputs should use the first listed container."
  }
}

run "todo_uses_azure_import_connect_path" {
  command = apply

  variables {
    todos_as_outputs = true
    import_containers = [
      {
        key                    = "hris"
        storage_account_name   = "existingacct0001"
        storage_container_name = "worklytics-import-hris"
      },
      {
        key                    = "badge"
        storage_account_name   = "existingacct0001"
        storage_container_name = "worklytics-import-badge"
      }
    ]
  }

  assert {
    condition     = strcontains(output.todo_markdown, "https://app.worklytics.co/analytics/connect/azure-import?")
    error_message = "TODO should deep-link to production app.worklytics.co /analytics/connect/azure-import."
  }

  assert {
    condition     = strcontains(output.todo_markdown, "container=worklytics-import-hris")
    error_message = "TODO should include a connect URL for each container."
  }

  assert {
    condition     = strcontains(output.todo_markdown, "container=worklytics-import-badge")
    error_message = "TODO should include a connect URL for each container."
  }

  assert {
    condition     = strcontains(output.todo_markdown, "Choose a parser")
    error_message = "TODO should tell the customer to choose a parser."
  }
}

run "todo_uses_custom_worklytics_host" {
  command = apply

  variables {
    todos_as_outputs = true
    worklytics_host  = "analytics.example.com"
    import_containers = [
      {
        storage_account_name   = "existingacct0001"
        storage_container_name = "worklytics-import-hris"
      }
    ]
  }

  assert {
    condition     = strcontains(output.todo_markdown, "https://analytics.example.com/analytics/connect/azure-import?")
    error_message = "TODO should use worklytics_host when overridden (custom domain)."
  }

  assert {
    condition     = !strcontains(output.todo_markdown, "https://app.worklytics.co/")
    error_message = "Custom worklytics_host should replace the production default in TODOs."
  }
}

run "rejects_worklytics_host_url" {
  command = plan

  variables {
    worklytics_host = "https://app.worklytics.co"
  }

  expect_failures = [
    var.worklytics_host,
  ]
}

run "rejects_invalid_import_containers_account_name" {
  command = plan

  variables {
    import_containers = [
      {
        storage_account_name   = "NOT-VALID"
        storage_container_name = "ok-container"
      }
    ]
  }

  expect_failures = [
    var.import_containers,
  ]
}
