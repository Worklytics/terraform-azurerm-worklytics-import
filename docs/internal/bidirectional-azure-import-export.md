# Bidirectional Azure import + export (internal)

This module is published as **import** infrastructure: grant a Worklytics tenant GCP service
account access to customer Azure Blob Storage via one Entra app and Google→Entra WIF.

Non-proxy customers often need the **reverse** as well (Worklytics writing datasets into Azure).
Creating a second Entra app for that is wasteful: the federated credential is already the tenant
SA, and blob data-plane RBAC is the same role (`Storage Blob Data Contributor`). Export should be
an option on **this** module, not a second customer-facing Azure AD application.

## Why this lives on the import module

| Customer shape | Import path today | Export path |
|----------------|-------------------|-------------|
| **Proxy** (Psoxy / hosted proxy) | Connector traffic already lands in Worklytics via the proxy Terraform modules. This Azure import module is usually **not** needed. | May still want Worklytics → Azure dataset export; that remains the existing `terraform-azure-worklytics-export` module, *or* this module with export enabled if they also want a unified app. |
| **Non-proxy** | Files / dumps in customer Azure that Worklytics should pull. **This module.** | Same customer usually also wants Worklytics to push analytics exports into Azure. Same WIF identity, extra container(s). |

So: proxy customers already have import covered elsewhere; non-proxy customers typically want
**both directions through blob**, and should not juggle two Entra apps.

## Proposed interface (do not implement until product URLs / export UX are confirmed)

Mirror import. Keep the singular convenience variables **and** an optional list.

```hcl
variable "enable_export" {
  type        = bool
  default     = false
  description = "If true, also grant this module's Entra app access to export/sink container(s)."
}

variable "export_storage_account_name" {
  type     = string
  default  = null
  nullable = true
}

variable "export_storage_container_name" {
  type     = string
  default  = null
  nullable = true
}

variable "export_containers" {
  type = list(object({
    key                    = optional(string)
    resource_group_name    = optional(string)
    storage_account_name   = optional(string)
    storage_container_name = optional(string)
  }))
  default = []
}
```

Semantics (same as import):

- `enable_export = false` (default): no export containers, no extra RBAC. Import-only, today's
  behavior.
- `enable_export = true` and singular export names null, list empty: **create** one sink account
  (or reuse the import-created account if we decide to share) + one `…export-container`.
- Pass singular names to reuse an existing sink.
- `export_containers` for additional sinks; list-only when singular export names are both null.

Alternative to `enable_export`: treat a non-empty `export_containers` / non-null
`export_storage_account_name` as the enable signal, so callers do not need a separate bool. Prefer
one explicit bool so "create a default sink" is not accidental.

## Identity: one Entra app

Keep a single:

- `azuread_application.worklytics`
- `azuread_service_principal.worklytics`
- `azuread_application_federated_identity_credential.worklytics`
  (`issuer = https://accounts.google.com`, `subject = worklytics_tenant_id`)

Do **not** create a second app when export is enabled. Worklytics already authenticates as that
app; import vs export is which container it reads or writes, plus which connection the customer
creates in the Worklytics UI.

Display name / `resource_name_prefix` may stay `worklytics-import-` for compatibility, or grow a
neutral default (`worklytics-azure-`) in a later major version. Not worth a breaking rename for
0.1.x; document that the app is the Worklytics Azure identity, not import-specific.

## Storage + RBAC

Per export target, same as import:

| Role | Scope |
|------|--------|
| Storage Blob Data Contributor | container |
| Storage Blob Delegator | storage account (once per unique account) |

Contributor already covers write, so export does not need a stronger role. Optionally we could
narrow **import** to Reader later; do not do that if Worklytics writes ingest checkpoints, and do
not split roles between directions unless product requires it (one SP, one role, less confusion).

Created export storage: either a second account (`w8se…` prefix) or a second container on the
import account. Prefer a **separate container** on the created import account when the module
created that account, so customers are not billed for two accounts by default. If they passed an
existing import account, still create a distinct export container (or honor names they pass).

Never point import and export at the same container unless the caller explicitly passed the same
names (allow it; do not dedupe RBAC — Terraform `for_each` on scope would collapse duplicates).

## Outputs and TODOs

- `export_containers` map analogous to `import_containers`
- `export_storage_account_name` / `export_storage_container_name` for the primary sink
- Extend the TODO markdown with the export deep-link
  (`/analytics/data-export/connect?type=AZURE_BLOB_STORAGE&…`) using the same `clientId` /
  `tenantId` as import
- Keep import TODO when import targets exist (they always do in the current module)

## Tests

- Unit: `enable_export = false` → zero export containers / extra role assignments
- Unit: `enable_export = true` → one created sink container; Contributor on it; still one Entra app
- Unit: reuse export names; list of extra export containers
- e2e (later): after import round-trip, PUT/GET on the export container as the same GCP identity

## Open questions

1. Product: confirm export connect URL and required fields (container, account, client id, tenant
   id) still match `terraform-azure-worklytics-export`.
2. Share one created storage account vs two. Default recommendation: one account, two containers.
3. Whether proxy-hosted customers should be told "do not use this module for import" in the public
   README (probably a short Usage note, not this internal doc).
4. Deprecate / wrap `terraform-azure-worklytics-export` once this option exists, so non-proxy
   customers have one registry module for Azure.

## Implementation sketch

1. Extract the import-target locals/resources into a reusable pattern (local maps +
   `azurerm_storage_container` / role assignment `for_each`) — already done for import.
2. Add export variables and a second target map (`local.export_targets`) feeding the same created
   account when `create_account` is true on an export target and an import account was created.
3. Concatenate unique account IDs for Delegator; union Contributor assignments (keyed
   `import/…` vs `export/…` so identical scopes cannot clash).
4. Docs: public README "optional export" section; keep this file as the rationale for proxy vs
   non-proxy.
