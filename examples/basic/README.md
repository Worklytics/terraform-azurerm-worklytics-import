# Basic example (module development / CI)

This directory is **not** a production starter. It exists so we can `terraform apply` the module
from a local checkout (GitHub Actions and local iteration).

- `source = "../../"` tests the code in this repo, not a published version.
- `backend "local"` keeps CI state on the runner. **Do not use a local backend in
  production.**

Customer-facing usage (Terraform Registry source, your own providers and remote state) is in:

- the [root README](../../README.md)
- [examples/basic-remote](../basic-remote/)

## Usage for Development

Within `examples/basic/` (eg, here), create a `terraform.tfvars` file with the following content,
customizing Azure Tenant ID, subscription, resource group, and Worklytics Tenant ID as needed.

Omit `storage_account_name` to have the module create a storage account; set it to reuse one.

```hcl
worklytics_tenant_id   = "123456712345671234567"
azure_tenant_id        = "aaaa8888-4444-5555-6666-777777777777"
azure_subscription_id  = "bbbb9999-4444-5555-6666-777777777777"
resource_group_name    = "my-resource-group-name"
# storage_account_name = "myexistingaccount" # optional; omit to create
resource_name_prefix   = "my-worklytics-data-import-" # Optional
```

Then test the example:

```shell
terraform init
terraform apply
```
