# example of consuming this module from the Terraform Registry once published

module "worklytics-import" {
  source  = "Worklytics/worklytics-import/azure"
  version = "~> 0.1.0"

  # numeric ID of your Worklytics Tenant SA (21-digit unique ID, not the email)
  worklytics_tenant_id = "123123123123123123123"

  azure_tenant_id     = "11111111-1111-1111-1111-111111111111"
  resource_group_name = "worklytics"

  # omit storage_account_name to create an account in the resource group
  # storage_account_name = "myexistingaccount"
}
