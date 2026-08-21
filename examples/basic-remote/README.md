# Registry example (customer-facing)

Copy this pattern into your own root module. `source` / `version` are the Terraform Registry
coordinates. Configure `azurerm` and `azuread` providers and a **remote** backend in that root
module; this file omits them so it stays a short snippet.

This example is **import only** (customer Azure Blob → Worklytics). For Worklytics → your Azure
tenant, use [`terraform-azurerm-worklytics-export`](https://github.com/Worklytics/terraform-azurerm-worklytics-export).

See the [root README](../../README.md) for the full variable set and for why both providers are
required.
