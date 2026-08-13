# -----------------------------------------------------------------------------
# Simple Lakebase deliverable for the app team:
#   project  ->  production branch (auto-created)  ->  sized primary endpoint
#   + a Unity Catalog catalog registered for the project.
#
# Intentionally NOT here:
#   - Branching. The APP owns branching at runtime: it creates an ephemeral RW
#     branch each day, merges changes back to the lakehouse, drops the RW branch,
#     and takes a fresh snapshot at end of day. Terraform must not manage
#     branches or it will fight the app.
#   - HA / readable secondaries / autoscaling policy / suspension. These are
#     tuned from the UI once the app team finalizes the configuration.
# -----------------------------------------------------------------------------

# Project — auto-provisions the `production` branch and a `primary` RW endpoint.
resource "databricks_postgres_project" "this" {
  project_id      = var.project_id
  purge_on_delete = var.purge_on_delete
  spec = {
    pg_version   = var.pg_version
    display_name = var.project_display_name
  }
}

# Size the production endpoint. We adopt the auto-created `primary`
# (replace_existing) and set only the instance size — nothing else, so the app
# team stays free to change autoscaling/HA/suspension from the UI later.
resource "databricks_postgres_endpoint" "prod_primary" {
  endpoint_id      = "primary"
  parent           = "${databricks_postgres_project.this.name}/branches/production"
  replace_existing = true

  spec = {
    endpoint_type            = "ENDPOINT_TYPE_READ_WRITE"
    autoscaling_limit_min_cu = var.prod_min_cu
    autoscaling_limit_max_cu = var.prod_max_cu
  }

  depends_on = [databricks_postgres_project.this]
}

# Register the Lakebase database as a Unity Catalog catalog — the app team's
# governed entry point to the project.
# NOTE: requires CREATE CATALOG on the metastore for whoever runs this.
resource "databricks_postgres_catalog" "this" {
  catalog_id = var.uc_catalog_id
  spec = {
    branch                     = "${databricks_postgres_project.this.name}/branches/production"
    postgres_database          = var.uc_catalog_postgres_database
    create_database_if_missing = false
  }
  depends_on = [databricks_postgres_project.this]
}
