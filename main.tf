data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  # This is the recommended value from MSFT, as it is what Entra expects in the "aud" claim of
  # the token. See docs:
  # https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation-create-trust?pivots=identity-wif-apps-methods-azp#important-considerations-and-restrictions
  federated_identity_audience = "api://AzureADTokenExchange"

  container_name_prefix = replace(var.resource_name_prefix, "_", "-")

  import_targets_list = [
    for i, loc in var.import_containers : {
      key = coalesce(
        loc.key,
        join("-", compact([loc.storage_account_name, loc.storage_container_name])),
        i == 0 ? "import" : format("import-%02d", i)
      )
      resource_group_name    = coalesce(loc.resource_group_name, var.resource_group_name)
      storage_account_name   = loc.storage_account_name
      storage_container_name = loc.storage_container_name
    }
  ]

  import_targets = {
    for loc in local.import_targets_list : loc.key => {
      key                    = loc.key
      resource_group_name    = loc.resource_group_name
      storage_account_name   = loc.storage_account_name
      storage_container_name = loc.storage_container_name
      create_account         = loc.storage_account_name == null
      create_container       = loc.storage_account_name == null || loc.storage_container_name == null
      generated_container_name = coalesce(
        loc.storage_container_name,
        loc.key == "import" ? "${local.container_name_prefix}container" : "${local.container_name_prefix}container-${replace(lower(loc.key), "_", "-")}"
      )
    }
  }

  create_storage_account = anytrue([
    for t in local.import_targets : t.create_account
  ])
}

resource "random_id" "storage_account" {
  count = local.create_storage_account ? 1 : 0

  # 8 bytes → 16 hex chars; with the `w8si` prefix this is a 20-char globally unique name
  # (Azure storage account names are 3-24 lowercase alphanumeric).
  byte_length = 8
}

data "azurerm_storage_account" "existing" {
  for_each = {
    for k, t in local.import_targets : k => t if t.storage_account_name != null
  }

  name                = each.value.storage_account_name
  resource_group_name = each.value.resource_group_name
}

# trivy:ignore:AVD-AZU-0012 Public network access is required so Worklytics (GCP) can pull objects.
# trivy:ignore:AVD-AZU-0057 Queue/table analytics logging is not the blob ingest path; Azure Monitor diagnostics need a customer-owned destination.
# trivy:ignore:AVD-AZU-0058 LRS is intentional for transient ingest storage; GRS is a customer cost/durability choice (pass an existing account).
resource "azurerm_storage_account" "worklytics" {
  count = local.create_storage_account ? 1 : 0

  # Globally unique, valid storage account name. Prefix is not used here because it may
  # contain hyphens and would be truncated if mixed with a uniqueness suffix.
  name                              = "w8si${random_id.storage_account[0].hex}"
  resource_group_name               = var.resource_group_name
  location                          = coalesce(var.location, data.azurerm_resource_group.this.location)
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  infrastructure_encryption_enabled = true
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false

  blob_properties {
    # Soft-delete recovery window, not a TTL for live objects.
    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
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
  created_storage_account_name = local.create_storage_account ? azurerm_storage_account.worklytics[0].name : null
  created_storage_account_id   = local.create_storage_account ? azurerm_storage_account.worklytics[0].id : null

  import_targets_with_account = {
    for k, t in local.import_targets : k => merge(t, {
      resolved_account_name = t.create_account ? local.created_storage_account_name : t.storage_account_name
      resolved_account_id   = t.create_account ? local.created_storage_account_id : data.azurerm_storage_account.existing[k].id
    })
  }
}

resource "azurerm_storage_container" "import" {
  for_each = {
    for k, t in local.import_targets_with_account : k => t if t.create_container
  }

  name                  = each.value.generated_container_name
  storage_account_id    = each.value.resolved_account_id
  container_access_type = "private"
}

locals {
  resolved_import_targets = {
    for k, t in local.import_targets_with_account : k => {
      key                    = k
      resource_group_name    = t.resource_group_name
      storage_account_name   = t.resolved_account_name
      storage_account_id     = t.resolved_account_id
      storage_container_name = t.generated_container_name
      storage_container_resource_manager_id = (
        t.create_container
        ? azurerm_storage_container.import[k].id
        : "${t.resolved_account_id}/blobServices/default/containers/${t.generated_container_name}"
      )
    }
  }

  first_import_key = local.import_targets_list[0].key
  first_import     = local.resolved_import_targets[local.first_import_key]

  connect_urls = {
    for k, t in local.resolved_import_targets : k => join("", [
      "https://${var.worklytics_host}/analytics/connect/azure-import",
      "?container=${urlencode(t.storage_container_name)}",
      "&storageAccount=${urlencode(t.storage_account_name)}",
      "&clientId=${urlencode(azuread_application.worklytics.client_id)}",
      "&tenantId=${urlencode(var.azure_tenant_id)}",
    ])
  }

  # One delegator assignment per distinct existing account (plus the created account).
  # Group so two containers on the same account do not produce duplicate for_each keys.
  existing_import_accounts = {
    for t in values(local.import_targets) :
    "${t.resource_group_name}/${t.storage_account_name}" => t...
    if !t.create_account
  }

  # Delegator is account-scoped; key by static names so for_each is known at plan time
  # (account resource IDs are not known until apply when this module creates the account).
  import_delegator_scopes = merge(
    local.create_storage_account ? {
      "__created__" = azurerm_storage_account.worklytics[0].id
    } : {},
    {
      for key, ts in local.existing_import_accounts :
      "existing-${replace(key, "/", "-")}" => data.azurerm_storage_account.existing[ts[0].key].id
    }
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

# Read/write blobs in each import container (ingest + status/checkpoint objects).
# azuread 3.x `id` is `/servicePrincipals/{guid}`; Azure RBAC requires the object GUID.
resource "azurerm_role_assignment" "import_contributor" {
  for_each = local.resolved_import_targets

  scope                            = each.value.storage_container_resource_manager_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azuread_service_principal.worklytics.object_id
  skip_service_principal_aad_check = true
}

# User Delegation Key via Azure SDK (account-level; keys cannot be requested at container scope).
resource "azurerm_role_assignment" "import_delegator" {
  for_each = local.import_delegator_scopes

  scope                            = each.value
  role_definition_name             = "Storage Blob Delegator"
  principal_id                     = azuread_service_principal.worklytics.object_id
  skip_service_principal_aad_check = true
}

locals {
  tenant_identity_note = var.worklytics_tenant_sa_email == null ? var.worklytics_tenant_id : "${var.worklytics_tenant_sa_email} (${var.worklytics_tenant_id})"

  import_todo_rows = join("\n", [
    for loc in local.import_targets_list :
    "  - ${loc.key}: account `${local.resolved_import_targets[loc.key].storage_account_name}`, container `${local.resolved_import_targets[loc.key].storage_container_name}`"
  ])

  connect_todo_rows = join("\n", [
    for loc in local.import_targets_list :
    "  - ${loc.key}: `${local.connect_urls[loc.key]}`"
  ])

  manual_todo_rows = join("\n", [
    for loc in local.import_targets_list :
    "  - ${loc.key}: Container `${local.resolved_import_targets[loc.key].storage_container_name}`, Storage Account `${local.resolved_import_targets[loc.key].storage_account_name}`"
  ])

  todo_content = <<EOT
# Configure Data Import in Worklytics

1. Ensure you're authenticated with Worklytics. Either sign-in at [https://${var.worklytics_host}](https://${var.worklytics_host})
  with your organization's SSO provider *or* request OTP link from your Worklytics support.
2. Open each connect URL below. Choose a parser (or define a custom one) and click Connect:
${local.connect_todo_rows}

Import containers granted to Worklytics:
${local.import_todo_rows}

Alternatively, you may follow the manual instructions below:

1. Visit [https://${var.worklytics_host}](https://${var.worklytics_host})
  (or login into Worklytics, and navigate to Manage --> Import Data).
2. Create an Azure Blob Storage import connection for each container:
${local.manual_todo_rows}
  Shared values for every connection:
  - Client ID: ${azuread_application.worklytics.client_id}
  - Tenant ID: ${var.azure_tenant_id}
  - Worklytics tenant identity: ${local.tenant_identity_note}

Write objects you want Worklytics to ingest into the container(s). Worklytics authenticates with
Entra via workload identity federation as the GCP service account above, then reads (and may
write ingest checkpoints to) those containers.
EOT
}

resource "local_file" "todo" {
  count = var.todos_as_local_files ? 1 : 0

  filename = "TODO - configure import in worklytics.md"
  content  = local.todo_content
}
