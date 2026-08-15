variable "resource_name_prefix" {
  type        = string
  description = "Prefix to give to names of infra created by this module, where applicable."
  default     = "worklytics-import-"
}

variable "worklytics_tenant_id" {
  type        = string
  description = <<-EOT
    Numeric unique ID of your Worklytics tenant's GCP service account (obtain from the Worklytics
    app). This is a 21-digit value used as the subject of the Entra federated identity credential.
    It is the same identifier used by the AWS/Azure export modules; it is *not* the SA email.
  EOT

  validation {
    condition     = can(regex("^\\d{21}$", var.worklytics_tenant_id))
    error_message = "`worklytics_tenant_id` must be a 21-digit numeric value."
  }
}

variable "worklytics_tenant_sa_email" {
  type        = string
  description = <<-EOT
    Optional email of your Worklytics tenant's GCP service account. Used only in generated
    instructions; federation is keyed by `worklytics_tenant_id`.
  EOT
  default     = null
}

variable "azure_tenant_id" {
  type        = string
  description = "Entra (Azure AD) tenant ID. Used for Worklytics connection instructions and deep-links."
}

variable "resource_group_name" {
  type        = string
  description = <<-EOT
    Resource group that contains (or will contain) the storage account. Must already exist. If
    `storage_account_name` is omitted, the created account is placed in this group.
  EOT
}

variable "location" {
  type        = string
  description = <<-EOT
    Azure region for a storage account created by this module. If null, the resource group's
    location is used. Ignored when `storage_account_name` is provided.
  EOT
  default     = null
}

variable "storage_account_name" {
  type        = string
  description = <<-EOT
    Existing Azure storage account to use as the import landing zone. If null, this module
    creates a storage account in `resource_group_name`.
  EOT
  default     = null
  nullable    = true

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "`storage_account_name` must be 3-24 lowercase letters and numbers."
  }
}

variable "storage_container_name" {
  type        = string
  description = <<-EOT
    Existing blob container to use as the import landing zone. If null, this module creates one.
    Providing both `storage_account_name` and `storage_container_name` skips storage creation
    entirely; the module only grants Worklytics access.
  EOT
  default     = null
  nullable    = true

  validation {
    condition = var.storage_container_name == null || can(regex(
      "^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$",
      var.storage_container_name
    ))
    error_message = "`storage_container_name` must be 3-63 chars of lowercase letters, numbers, and hyphens."
  }
}

variable "owners" {
  type        = set(string)
  description = "Object IDs set as owners of the Entra application created for Worklytics."
  default     = []
}

variable "federated_identity_description" {
  type        = string
  description = "Optional description of the federated identity credential."
  default     = "Allows the Worklytics tenant GCP service account to access this import container."
}

variable "federated_identity_issuer" {
  type        = string
  description = <<-EOT
    URL of the external identity provider; must match the issuer claim of the token being
    exchanged. The combination of issuer and subject must be unique on the app.
  EOT
  default     = "https://accounts.google.com"
}

variable "worklytics_host" {
  type        = string
  description = "Host of the Worklytics instance where the tenant resides (e.g. app.worklytics.co)."
  default     = "app.worklytics.co"
}

variable "todos_as_outputs" {
  type        = bool
  description = <<-EOT
    Whether to render TODOs as outputs (useful if you're using Terraform Cloud/Enterprise, or
    somewhere else where the filesystem is not readily accessible to you).
  EOT
  default     = false
}

variable "todos_as_local_files" {
  type        = bool
  description = "Whether to render TODOs as flat files."
  default     = true
}
