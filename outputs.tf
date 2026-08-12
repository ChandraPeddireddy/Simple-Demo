output "project_name" {
  description = "Lakebase project resource name (projects/<id>)."
  value       = databricks_postgres_project.this.name
}

output "production_branch" {
  description = "Production branch resource name the app team connects to."
  value       = "${databricks_postgres_project.this.name}/branches/production"
}

output "prod_endpoint_host" {
  description = "Production primary (read-write) connection host."
  value       = try(databricks_postgres_endpoint.prod_primary.status.hosts.host, null)
}

output "uc_catalog_name" {
  description = "Unity Catalog catalog registered for the project (hand this to the app team)."
  value       = databricks_postgres_catalog.this.name
}
