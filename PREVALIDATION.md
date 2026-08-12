# Pre-validation — `simple-demo`

Checks that must pass **before** `terraform apply` will succeed. Run them
top-to-bottom (they're in dependency order); `preflight.sh` automates the same
set. Nothing here creates resources.

Auth for the CLI-based checks: set one of
- `export DATABRICKS_CONFIG_PROFILE=lakebase-sandbox`, or
- `source env.sh` (SP M2M: `DATABRICKS_HOST` + `DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET`).

---

## 1. Terraform installed, version ≥ 1.9

- **Validates:** the `terraform` binary exists and is new enough.
- **Why ≥ 1.9:** `variables.tf` uses a cross-variable validation (`prod_max_cu`
  references `prod_min_cu`), allowed only from Terraform 1.9.0. Older versions
  fail `validate`/`plan` with *"The condition for variable can only refer to the
  variable itself."* Enforced by `required_version = ">= 1.9.0"` in `versions.tf`.
- **Check:**
  ```bash
  terraform version
  ```
- **Pass:** `Terraform v1.9.x` or newer.
- **If it fails:** `brew install terraform` (or `brew upgrade terraform`).
