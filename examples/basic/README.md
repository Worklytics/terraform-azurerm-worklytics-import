# Basic Worklytics Import from Azure Blob Storage Example

We don't recommend *direct* use of this example, but rather use it as a reference for how to add
the Worklytics Import module to your own Terraform configuration or as a working example when
developing the module itself.

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
