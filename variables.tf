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
    Default resource group for created storage and for looking up accounts that do not set their
    own `resource_group_name`. Must already exist.
  EOT
}

variable "location" {
  type        = string
  description = <<-EOT
    Azure region for a storage account created by this module. If null, the resource group's
    location is used. Ignored when no account is created.
  EOT
  default     = null
}

variable "import_containers" {
  type = list(object({
    key                    = optional(string)
    resource_group_name    = optional(string)
    storage_account_name   = optional(string)
    storage_container_name = optional(string)
  }))
  description = <<-EOT
    Import landing zones (Azure blob containers). At least one is required. The default is a
    single created account and container.

    Each object may omit `storage_account_name` and/or `storage_container_name` to create them
    (created accounts share one module-managed account). Pass both names to reuse an existing
    container and only grant Worklytics access. Optional `key` is used in outputs, TODOs, and
    generated container names; optional `resource_group_name` overrides the module default when
    looking up an existing account.
  EOT
  default     = [{}]

  validation {
    condition     = length(var.import_containers) >= 1
    error_message = "`import_containers` must contain at least one landing zone."
  }

  validation {
    condition = alltrue([
      for loc in var.import_containers :
      loc.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", loc.storage_account_name))
    ])
    error_message = "Each import_containers.storage_account_name must be 3-24 lowercase letters and numbers."
  }

  validation {
    condition = alltrue([
      for loc in var.import_containers :
      loc.storage_container_name == null || can(regex(
        "^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$",
        loc.storage_container_name
      ))
    ])
    error_message = "Each import_containers.storage_container_name must be a valid Azure container name."
  }
}

variable "blob_soft_delete_retention_days" {
  type        = number
  description = <<-EOT
    Soft-delete retention (days) on a storage account *created* by this module. This is the
    recovery window after a blob is deleted; it does not expire live objects. Ignored when
    reusing an existing account.
  EOT
  default     = 30

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "`blob_soft_delete_retention_days` must be between 1 and 365."
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
  default     = "Allows the Worklytics tenant GCP service account to access import containers."
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
