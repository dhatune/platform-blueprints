output "workspace_id" {
  description = "Workspace identifier, consumed by diagnostic settings."
  value       = azurerm_log_analytics_workspace.this.id
}
