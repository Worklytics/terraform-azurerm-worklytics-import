# Worklytics Import from Azure Terraform Module

[![Latest Release](https://img.shields.io/github/v/release/Worklytics/terraform-azurerm-worklytics-import)](https://github.com/Worklytics/terraform-azurerm-worklytics-import/releases/latest)
[![tests](https://img.shields.io/github/actions/workflow/status/Worklytics/terraform-azurerm-worklytics-import/terraform_integration.yaml?label=tests)](https://github.com/Worklytics/terraform-azurerm-worklytics-import/actions?query=branch%3Amain)

This module creates infra to support **importing** data from [Azure Blob Storage] into Worklytics
(customer premises → Worklytics). It does **not** set up the reverse path: it does not create an
export container or grant Worklytics write access for data export.

| Data flow | Module |
|-----------|--------|
| Customer premises → Worklytics | this module (`Worklytics/worklytics-import/azurerm`) |
| Worklytics → customer premises | [`terraform-azurerm-worklytics-export`](https://github.com/Worklytics/terraform-azurerm-worklytics-export) (`Worklytics/worklytics-export/azurerm`) |

Use the export module if Worklytics should write results or dumps into your Azure tenant. Do not
compose this import module as a stand-in for that, and do not reuse an import container as an
export destination.

It is intended for **non-proxy** Worklytics customers (files or dumps in your Azure tenant that
Worklytics should pull). If you use Worklytics with a [Psoxy] proxy, do not use this module for
that path: the [proxy Terraform modules] already provide equivalent functionality for connecting
sanitized data to Worklytics.

It is intended for the [Terraform Registry](https://registry.terraform.io/modules/Worklytics/worklytics-import/azurerm/latest)
(`Worklytics/worklytics-import/azurerm`).

If it does not meet your needs, feel free to directly copy the `main.tf` file into your own Terraform
configuration and adapt it to your requirements.

## What it provisions

1. **Storage (optional, import only)** — one or more Azure blob containers via `import_containers`.
   Omit names to create an account and container; pass existing names to only grant Worklytics
   access. This is not an export container.
2. **Entra application + service principal** with a federated identity credential that trusts your
   Worklytics tenant's GCP service account (`issuer = https://accounts.google.com`,
   `subject = worklytics_tenant_id`).
3. **RBAC** so that identity can read and write blobs in each import container (`Storage Blob Data
   Contributor` on the container, `Storage Blob Delegator` on the account).

Worklytics then exchanges a Google ID token for an Entra access token and pulls objects from the
container (and may write ingest checkpoints). That write is for import bookkeeping, not a data
export.

## Usage

from Terraform registry (once published):
```hcl
module "worklytics_import" {
  source  = "Worklytics/worklytics-import/azurerm"
  version = "~> 0.1.0"

  # numeric ID of your Worklytics Tenant SA (21-digit unique ID, not the email)
  worklytics_tenant_id = "123456789012345678901"
  azure_tenant_id      = "11111111-1111-1111-1111-111111111111"
  resource_group_name  = "worklytics"
}
```

via GitHub:
```hcl
module "worklytics_import" {
  source = "git::https://github.com/worklytics/terraform-azurerm-worklytics-import/?ref=v0.1.0"

  worklytics_tenant_id = "123456789012345678901"
  azure_tenant_id      = "11111111-1111-1111-1111-111111111111"
  resource_group_name  = "worklytics"
}
```

The calling configuration must declare `azurerm` and `azuread` providers. This module does not
configure providers (so it can be composed into an existing Azure workspace).

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azuread" {
  tenant_id = var.azure_tenant_id
}
```

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `worklytics_tenant_id` | yes | | 21-digit unique ID of the Worklytics tenant GCP SA |
| `azure_tenant_id` | yes | | Entra tenant ID (for instructions / deep-link) |
| `resource_group_name` | yes | | Existing resource group for created storage and lookups |
| `import_containers` | no | `[{}]` | Blob containers to import from; omit names to create, or pass existing names to reuse. At least one required |
| `blob_auto_delete_after_days` | no | `1825` (5 years) | Auto-delete blobs on a *created* account after this many days since creation; `null` omits the policy. Does not block earlier deletes |
| `blob_soft_delete_retention_days` | no | `30` | Soft-delete recovery window on a *created* account (not a live-object TTL) |
| `location` | no | RG location | Region used only when creating a storage account |
| `worklytics_tenant_sa_email` | no | `null` | SA email, documentation only |
| `resource_name_prefix` | no | `worklytics-import-` | Prefix for created Entra / container names |
| `owners` | no | `[]` | Entra object IDs set as owners of the application |
| `worklytics_host` | no | `app.worklytics.co` | Hostname for connect TODOs / deep-links (prod by default; override for a custom domain) |

Your Worklytics tenant identity is the **numeric unique ID** of the tenant's GCP service account
(the same value used by other Worklytics Terraform modules, including the Azure *export* module). The SA email cannot be used as the
federated credential subject. Obtain the ID from the Worklytics app, or:

```bash
gcloud iam service-accounts describe EMAIL --format='value(uniqueId)'
```

## Outputs

#### `storage_account_name` / `storage_account_id`
The storage account for the first `import_containers` entry (created or reused).

#### `storage_container_name` / `storage_container_resource_manager_id`
The blob container for the first `import_containers` entry.

#### `import_containers`
Map of every import container, keyed by target key. Use this when composing extra RBAC or when
the customer has several ingest locations.

#### `application_client_id`
Entra application (client) ID. Worklytics uses this when exchanging a Google ID token for an Azure
access token.

#### `service_principal_object_id`
Object ID of the service principal granted blob access. Compose with additional `azurerm_role_assignment`
resources if you use a customer-managed encryption key or extra locks.

#### `todo_markdown`
Rendered when `todos_as_outputs = true`.

## Compatibility

This module is meant for use with Terraform 1.3+ and:

- `azurerm` `>= 4.0` (storage + Azure RBAC)
- `azuread` `>= 2.47` (Entra app, service principal, federated identity credential)

Both providers are required: HashiCorp splits Azure Resource Manager from Entra ID. This module
does not configure provider blocks; the caller must.

If you find incompatibilities, please open an issue.

## Usage Tips

### Existing storage account / container

Pass both names in `import_containers` to skip storage creation and only grant Worklytics access:

```hcl
module "worklytics_import" {
  source = "Worklytics/worklytics-import/azurerm"

  worklytics_tenant_id = "123456789012345678901"
  azure_tenant_id      = "11111111-1111-1111-1111-111111111111"
  resource_group_name  = "worklytics"

  import_containers = [
    {
      storage_account_name   = "myexistingaccount"
      storage_container_name = "worklytics-import"
    }
  ]
}
```

If you omit only `storage_container_name`, the module creates a private container on the existing
account.

### Auto-delete (max age)

Accounts *created* by this module get a lifecycle rule that deletes block blobs 5 years after
creation (`blob_auto_delete_after_days = 1825`). Lower that value to expire sooner, or set it to
`null` to skip a lifecycle policy. This never blocks you from deleting objects yourself, and is
not applied to existing accounts you pass in.

### Multiple import containers

Pass every import container in `import_containers`. Omit names on an item to create that
container; pass both names to reuse an existing one:

```hcl
module "worklytics_import" {
  source = "Worklytics/worklytics-import/azurerm"

  worklytics_tenant_id = "123456789012345678901"
  azure_tenant_id      = "11111111-1111-1111-1111-111111111111"
  resource_group_name  = "worklytics"

  import_containers = [
    { key = "hris" },
    {
      key                    = "badge"
      storage_account_name   = "myexistingaccount"
      storage_container_name = "worklytics-import-badge"
    },
    {
      key                    = "calendar"
      resource_group_name    = "other-rg"
      storage_account_name   = "anotheraccount"
      storage_container_name = "worklytics-import-calendar"
    }
  ]
}
```

The generated Worklytics connect TODO includes a URL per container.

### Permissions granted to Worklytics

| Role | Scope | Why |
|------|-------|-----|
| Storage Blob Data Contributor | container | Read/write/delete blobs (ingest + checkpoints; not a data export) |
| Storage Blob Delegator | storage account | User delegation keys used by Azure SDKs |

The federated credential trusts Google (`accounts.google.com`) as issuer and your
`worklytics_tenant_id` as subject, with audience `api://AzureADTokenExchange`.

## Development

This module is written and maintained by [Worklytics, Co.](https://worklytics.co/) and intended to
guide our customers in setting up their own infra to import data from Azure Blob Storage into
Worklytics (customer premises → Worklytics). For the reverse path, use
[`terraform-azurerm-worklytics-export`](https://github.com/Worklytics/terraform-azurerm-worklytics-export).

As this is [published as a Terraform module](https://developer.hashicorp.com/terraform/registry/modules/publish),
we will strive to follow [standard Terraform module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
and [style conventions](https://developer.hashicorp.com/terraform/language/syntax/style).

See [examples/basic/](examples/basic/) for a simple example of how to use this module.

### Releasing

Registry versions are **git tags** (`vX.Y.Z`) on `main`, not GitHub Releases. After a change is on
`main` and CI is green:

```bash
./tools/release.sh v0.1.0 --wait
```

That tags the current `origin/main` commit and pushes the tag. The tag-triggered workflow creates
the GitHub Release (notes / README badge). First-time listing on
[registry.terraform.io](https://registry.terraform.io/modules/Worklytics/worklytics-import/azurerm)
is a one-time Publish in the HashiCorp UI (`Worklytics/worklytics-import/azurerm`); later tags are
picked up by the Registry webhook.

### Tests

| Workflow | What it covers |
|----------|----------------|
| `terraform_lint.yaml` | `terraform fmt -check` |
| `terraform_validate.yaml` | `terraform init` / `validate` on `examples/basic`, plus `terraform test` unit tests |
| `terraform_integration.yaml` | Apply in a CI Azure subscription, then read/write a blob as the stand-in Worklytics GCP identity |
| `terraform_security.yaml` | Trivy IaC scan |

Unit tests live in [`tests/`](tests/) and use Terraform's native test framework with mocked
`azurerm` / `azuread` providers (no cloud credentials).

Integration tests authenticate to **Azure** (GitHub → Entra OIDC) to apply this module, and to
**GCP** (GitHub → WIF) to impersonate the stand-in Worklytics tenant SA. The test then exchanges a
Google ID token for an Entra token and PUTs/GETs a blob. Required GitHub secrets (public repo) or
variables (private repo):

| Name | Purpose |
|------|---------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GitHub Actions WIF provider |
| `GCP_SERVICE_ACCOUNT` | CI agent SA (e.g. `gh-actions-tf-azure-import@...`) |
| `ENTRA_ID_CLIENT_ID` | Entra app for GitHub OIDC |
| `ENTRA_ID_TENANT_ID` | Entra tenant |
| `AZURE_SUBSCRIPTION_ID` | Subscription that contains the CI resource group |
| `AZURE_RESOURCE_GROUP_NAME` | Pre-created sandbox resource group (Owner scoped to this RG) |

The CI agent SA must be able to impersonate the stand-in tenant SA
(`w8s-import-tf-ci@worklytics-ci.iam.gserviceaccount.com`). The Entra GitHub OIDC app must be able
to create storage accounts, Entra applications, and role assignments **in the CI resource group**
(not subscription-wide). The resource group is provisioned by `worklytics-infra` (`src/org-github`)
and is delete-locked; workflows must not create or delete it.

(c) 2026 Worklytics, Co

[Azure Blob Storage]: https://learn.microsoft.com/en-us/azure/storage/blobs/
[Psoxy]: https://github.com/Worklytics/psoxy
[proxy Terraform modules]: https://github.com/Worklytics/psoxy
