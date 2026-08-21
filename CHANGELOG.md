# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Changed
- Document that this module is import-only (customer premises → Worklytics). Outbound data
  (Worklytics → customer premises) uses [`terraform-azurerm-worklytics-export`](https://github.com/Worklytics/terraform-azurerm-worklytics-export).
- Connect TODOs deep-link to production `https://app.worklytics.co/analytics/connect/azure-import`
  by default (`worklytics_host` overrides the host for a custom domain).

### Added
- Initial module to set up Azure Blob Storage containers for importing data into Worklytics.
- Optional creation of a storage account and/or private blob containers via `import_containers`
  (at least one container; omit names to create, or pass existing names to reuse).
- Entra application, service principal, and Google → Entra federated identity credential keyed by
  the Worklytics tenant's 21-digit GCP service account unique ID.
- `Storage Blob Data Contributor` on each container and `Storage Blob Delegator` on each account.
- Configurable blob soft-delete retention (`blob_soft_delete_retention_days`, default 30) on
  accounts created by this module.
- Native `terraform test` unit tests (mocked providers) and a GitHub Actions integration test that
  applies the module in Azure and round-trips a blob as the federated GCP identity.
- Maintainer release helper (`tools/release.sh`) that tags `origin/main` only after required CI
  checks pass.
- Requires Terraform 1.3+, `azurerm` >= 4.0, and `azuread` >= 2.47.
- Published as `Worklytics/worklytics-import/azurerm`
  (`terraform-azurerm-worklytics-import`), matching the HashiCorp Azure provider slug.

### Fixed
- Azure RBAC assignments use the service principal object GUID (`object_id`). azuread 3.x
  `id` is a Graph resource path (`/servicePrincipals/{guid}`), which Azure rejects.
