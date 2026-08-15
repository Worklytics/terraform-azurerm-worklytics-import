output "storage_account_name" {
  value       = local.storage_account_name
  description = "Name of the Azure storage account used as the import landing zone."
}

output "storage_account_id" {
  value       = local.storage_account_id
  description = "Resource ID of the Azure storage account used as the import landing zone."
}

output "storage_container_name" {
  value       = local.container_name
  description = "Name of the blob container Worklytics will read from / write to."
}

output "storage_container_resource_manager_id" {
  value       = local.container_resource_manager_id
  description = "ARM resource ID of the blob container. Useful for additional role assignments."
}

output "application_client_id" {
  value       = azuread_application.worklytics.client_id
  description = "Entra application (client) ID Worklytics uses when exchanging a Google ID token."
}

output "service_principal_object_id" {
  value       = azuread_service_principal.worklytics.id
  description = "Object ID of the Entra service principal granted blob access. Useful for composing extra RBAC."
}

output "todo_markdown" {
  value       = var.todos_as_outputs ? local.todo_content : null
  description = "Actions that must be performed outside of Terraform (markdown format)."
}
