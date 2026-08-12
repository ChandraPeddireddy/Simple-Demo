terraform {
  # >= 1.9 for cross-variable validation (prod_max_cu references prod_min_cu).
  required_version = ">= 1.9.0"

  required_providers {
    databricks = {
      source = "databricks/databricks"
      # >= 1.126.0 exposes databricks_postgres_project/_endpoint/_catalog.
      version = ">= 1.126.0, < 2.0"
    }
  }
}

provider "databricks" {
  # Auth via env (DATABRICKS_HOST + DATABRICKS_CLIENT_ID/SECRET, or a profile
  # through DATABRICKS_CONFIG_PROFILE). Nothing hardcoded here.
}
