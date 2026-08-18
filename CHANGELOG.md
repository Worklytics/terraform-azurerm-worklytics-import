# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added
- Initial module to set up an Azure Blob Storage landing zone for importing data into Worklytics.
- Optional creation of a storage account and/or private blob container; existing names are reused
  when provided. Additional ingest locations via `import_containers`.
- Entra application, service principal, and Google → Entra federated identity credential keyed by
  the Worklytics tenant's 21-digit GCP service account unique ID.
- `Storage Blob Data Contributor` on the container and `Storage Blob Delegator` on the account.
- Native `terraform test` unit tests (mocked providers) and a GitHub Actions integration test that
  applies the module in Azure and round-trips a blob as the federated GCP identity.
- Maintainer release helper (`tools/release.sh`) that tags `origin/main` only after required CI
  checks pass.
- Requires Terraform 1.3+, `azurerm` >= 4.0, and `azuread` >= 2.47.
- Published as `Worklytics/worklytics-import/azurerm`
  (`terraform-azurerm-worklytics-import`), matching the HashiCorp Azure provider slug.
