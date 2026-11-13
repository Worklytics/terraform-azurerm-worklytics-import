# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - Unreleased

### Fixed
- CI integration apply no longer assigns `owners` on the Entra service principal (avoids a
  post-create Graph patch that failed with 403 for the GitHub OIDC principal).
- README badges and data-flow table render inline on GitHub and the Terraform Registry.

## [0.1.0] - Unreleased

Terraform module to import data from Azure Blob Storage into Worklytics (customer premises →
Worklytics). Published as `Worklytics/worklytics-import/azurerm`.
