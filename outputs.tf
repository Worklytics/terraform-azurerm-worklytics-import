output "storage_account_name" {
  value       = local.first_import.storage_account_name
  description = "Name of the Azure storage account for the first `import_containers` entry."
}

output "storage_account_id" {
  value       = local.first_import.storage_account_id
  description = "Resource ID of the Azure storage account for the first `import_containers` entry."
}

output "storage_container_name" {
  value       = local.first_import.storage_container_name
  description = "Name of the blob container for the first `import_containers` entry."
}

output "storage_container_resource_manager_id" {
  value       = local.first_import.storage_container_resource_manager_id
  description = "ARM resource ID of the first import container. Useful for additional role assignments."
}

output "import_containers" {
  value       = local.resolved_import_targets
  description = <<-EOT
    Map of all import containers keyed by target key. Each value has account name/id,
    container name, and container ARM id.
  EOT
}

output "application_client_id" {
  value       = azuread_application.worklytics.client_id
  description = "Entra application (client) ID Worklytics uses when exchanging a Google ID token."
}

output "service_principal_object_id" {
  value       = azuread_service_principal.worklytics.object_id
  description = "Object ID of the Entra service principal granted blob access. Useful for composing extra RBAC."
}

output "todo_markdown" {
  value       = var.todos_as_outputs ? local.todo_content : null
  description = "Actions that must be performed outside of Terraform (markdown format)."
}
