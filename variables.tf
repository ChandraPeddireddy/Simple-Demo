# -----------------------------------------------------------------------------
# Inputs. Copy terraform.tfvars.example -> terraform.tfvars and override.
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Lakebase project id (immutable; changing it recreates the project)."
  type        = string
  default     = "simple-demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 3-63 chars, lowercase alphanumeric or hyphens, not start/end with a hyphen."
  }
}

variable "project_display_name" {
  description = "Human-friendly name shown in the Databricks UI."
  type        = string
  default     = "Simple Demo"
}

variable "pg_version" {
  description = "PostgreSQL major version."
  type        = number
  default     = 17

  validation {
    condition     = contains([14, 15, 16, 17], var.pg_version)
    error_message = "pg_version must be one of: 14, 15, 16, 17."
  }
}

variable "purge_on_delete" {
  description = "How `terraform destroy` deletes the project. false = soft delete (7-day retention, project_id slug stays reserved); true = hard delete (frees the slug immediately). NOTE: default is `true` for now to keep dev/demo iteration easy (destroy + recreate the same project_id without waiting out the 7-day slug reservation). Set to `false` for production so a destroy cannot immediately and irreversibly drop the project."
  type        = bool
  default     = true
}

# --- Production instance size ------------------------------------------------
# Sensible starting point only. Autoscaling range, HA/readable secondaries, and
# suspension are intentionally NOT locked down here — the app team tunes those
# from the UI once the configuration is finalized.
variable "prod_min_cu" {
  description = "Autoscaling floor (CU) for the production endpoint."
  type        = number
  default     = 1

  validation {
    condition     = var.prod_min_cu >= 0.5 && var.prod_min_cu <= 32
    error_message = "prod_min_cu must be between 0.5 and 32."
  }
}

variable "prod_max_cu" {
  description = "Autoscaling ceiling (CU) for the production endpoint. max - min must be <= 16."
  type        = number
  default     = 2

  validation {
    condition     = var.prod_max_cu >= var.prod_min_cu && var.prod_max_cu <= 32 && (var.prod_max_cu - var.prod_min_cu) <= 16
    error_message = "prod_max_cu must be >= prod_min_cu, <= 32, and the spread (max - min) must be <= 16 CU."
  }
}

# --- Unity Catalog -----------------------------------------------------------
variable "uc_catalog_id" {
  description = "Name of the UC catalog to register for the Lakebase project (handed to the app team)."
  type        = string
  default     = "simple_demo"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]+$", var.uc_catalog_id))
    error_message = "uc_catalog_id must contain only letters, digits, and underscores."
  }
}

variable "uc_catalog_postgres_database" {
  description = "Postgres database the UC catalog exposes (Lakebase default)."
  type        = string
  default     = "databricks_postgres"
}
