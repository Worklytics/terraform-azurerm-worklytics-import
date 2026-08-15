data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  create_storage_account = var.storage_account_name == null
  # Only reuse a container when the caller supplied both account and container names.
  create_container = var.storage_account_name == null || var.storage_container_name == null

  # This is the recommended value from MSFT, as it is what Entra expects in the "aud" claim of
  # the token. See docs:
  # https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation-create-trust?pivots=identity-wif-apps-methods-azp#important-considerations-and-restrictions
  federated_identity_audience = "api://AzureADTokenExchange"

  container_name = coalesce(
    var.storage_container_name,
    "${replace(var.resource_name_prefix, "_", "-")}container"
  )
}

resource "random_id" "storage_account" {
  count = local.create_storage_account ? 1 : 0

  # 8 bytes → 16 hex chars; with the `w8si` prefix this is a 20-char globally unique name
  # (Azure storage account names are 3-24 lowercase alphanumeric).
  byte_length = 8
}

data "azurerm_storage_account" "existing" {
  count = local.create_storage_account ? 0 : 1

  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

# trivy:ignore:AVD-AZU-0012 Public network access is required so Worklytics (GCP) can pull objects.
resource "azurerm_storage_account" "worklytics" {
  count = local.create_storage_account ? 1 : 0

  # Globally unique, valid storage account name. Prefix is not used here because it may
  # contain hyphens and would be truncated if mixed with a uniqueness suffix.
  name                            = "w8si${random_id.storage_account[0].hex}"
  resource_group_name             = var.resource_group_name
  location                        = coalesce(var.location, data.azurerm_resource_group.this.location)
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = {
    purpose = "worklytics-import"
  }

  lifecycle {
    ignore_changes = [
      # don't conflict with tags customers might wish to add themselves
      tags,
    ]
  }
}

locals {
  storage_account_name = local.create_storage_account ? azurerm_storage_account.worklytics[0].name : var.storage_account_name
  storage_account_id   = local.create_storage_account ? azurerm_storage_account.worklytics[0].id : data.azurerm_storage_account.existing[0].id
}

resource "azurerm_storage_container" "worklytics" {
  count = local.create_container ? 1 : 0

  name                  = local.container_name
  storage_account_id    = local.storage_account_id
  container_access_type = "private"
}

locals {
  container_resource_manager_id = (
    local.create_container
    ? azurerm_storage_container.worklytics[0].id
    : "${local.storage_account_id}/blobServices/default/containers/${local.container_name}"
  )
}

# Entra application: storage container access via federated identity (GCP → Azure)
# https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application
resource "azuread_application" "worklytics" {
  display_name = "${var.resource_name_prefix}app"

  feature_tags {
    hide       = true
    enterprise = false
    gallery    = false
  }

  owners = var.owners
}

resource "azuread_service_principal" "worklytics" {
  client_id = azuread_application.worklytics.client_id

  owners = var.owners
}

resource "azuread_application_federated_identity_credential" "worklytics" {
  application_id = azuread_application.worklytics.id
  display_name   = "${var.resource_name_prefix}federated-identity"
  description    = var.federated_identity_description
  audiences      = [local.federated_identity_audience]
  issuer         = var.federated_identity_issuer
  subject        = var.worklytics_tenant_id
}

# Read/write blobs in the import container (ingest + status/checkpoint objects).
resource "azurerm_role_assignment" "role_contributor" {
  scope                            = local.container_resource_manager_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azuread_service_principal.worklytics.id
  skip_service_principal_aad_check = true
}

# User Delegation Key via Azure SDK (account-level; keys cannot be requested at container scope).
resource "azurerm_role_assignment" "role_delegator" {
  scope                            = local.storage_account_id
  role_definition_name             = "Storage Blob Delegator"
  principal_id                     = azuread_service_principal.worklytics.id
  skip_service_principal_aad_check = true
}

locals {
  tenant_identity_note = var.worklytics_tenant_sa_email == null ? var.worklytics_tenant_id : "${var.worklytics_tenant_sa_email} (${var.worklytics_tenant_id})"

  todo_content = <<EOT
# Configure Data Import in Worklytics

1. Ensure you're authenticated with Worklytics. Either sign-in at [https://${var.worklytics_host}](https://${var.worklytics_host})
  with your organization's SSO provider *or* request OTP link from your Worklytics support.
2. Visit `https://${var.worklytics_host}/analytics/data-import/connect?type=AZURE_BLOB_STORAGE&container=${local.container_name}&storageAccount=${local.storage_account_name}&clientId=${azuread_application.worklytics.client_id}&tenantId=${var.azure_tenant_id}`
3. Review any additional settings and click "Create Data Import".

Alternatively, you may follow the manual instructions below:

1. Visit [https://${var.worklytics_host}](https://${var.worklytics_host})
  (or login into Worklytics, and navigate to Manage --> Import Data).
2. Create a new Azure Blob Storage import connection with the following values:
  - Container Name: ${local.container_name}
  - Storage Account: ${local.storage_account_name}
  - Client ID: ${azuread_application.worklytics.client_id}
  - Tenant ID: ${var.azure_tenant_id}
  - Worklytics tenant identity: ${local.tenant_identity_note}

Write objects you want Worklytics to ingest into the container. Worklytics authenticates with
Entra via workload identity federation as the GCP service account above, then reads (and may
write ingest checkpoints to) the container.
EOT
}

resource "local_file" "todo" {
  count = var.todos_as_local_files ? 1 : 0

  filename = "TODO - configure import in worklytics.md"
  content  = local.todo_content
}
