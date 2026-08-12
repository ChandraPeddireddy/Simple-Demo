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

---

## 2. Databricks CLI — *optional*

- **Validates:** the `databricks` CLI binary exists.
- **NOT required to deploy.** The Databricks Terraform provider authenticates on
  its own from environment variables or `~/.databrickscfg` — it never calls the
  CLI. A locked-down environment with no CLI deploys via env-var auth (see
  Check #3), which is the normal CI/CD pattern anyway.
- **Only needed for convenience:** setting up a profile
  (`databricks auth login`), the verification commands
  (`current-user me`, `postgres get-endpoint`, `generate-database-credential`),
  and `preflight.sh`.
- **Check (if installed):**
  ```bash
  databricks version
  ```
- **Pass:** a recent unified CLI (`v0.2xx` or newer), **or** CLI absent and you
  deploy via env-var auth.
- **CLI-free verification instead:** `terraform plan` (proves auth), `terraform
  output` (endpoint host), and — for a Postgres token — a REST call (Check #3)
  or let the app mint its own token at runtime.

---

## 3. Databricks authentication configured

- **Validates:** Terraform can authenticate to the workspace as an identity with
  the right permissions.
- **Recommended for restricted environments — Service Principal (OAuth M2M), no
  CLI needed.** Three env vars:
  ```bash
  export DATABRICKS_HOST="https://adb-XXXXXXXX.azuredatabricks.net"
  export DATABRICKS_CLIENT_ID="<sp-application-id>"
  export DATABRICKS_CLIENT_SECRET="<sp-oauth-secret>"
  ```

### How to get each value from the Databricks workspace

| Value | Where to get it (UI) |
|-------|----------------------|
| `DATABRICKS_HOST` | The workspace URL in your browser's address bar, e.g. `https://adb-XXXX.azuredatabricks.net` (no trailing path). |
| Service principal + `DATABRICKS_CLIENT_ID` | **Settings → Identity and access → Service principals →** create or select an SP. Its **Application ID** is the client id. (Requires a workspace admin.) |
| `DATABRICKS_CLIENT_SECRET` | On that SP → **Secrets → Generate secret.** Copy the **Secret** — it is shown **once**. Note its expiry and store it in a secrets manager, never in git. |

> The SP must also be **entitled/granted** the permissions in Checks 5–7
> (workspace access, Lakebase, and — for the catalog — `CREATE CATALOG` on the
> metastore). Creating the SP does not grant these automatically.

- **Alternative — Personal Access Token (PAT):** **Settings → Developer →
  Access tokens → Generate new token**, then:
  ```bash
  export DATABRICKS_HOST="https://adb-XXXXXXXX.azuredatabricks.net"
  export DATABRICKS_TOKEN="<pat>"
  ```
  PATs are tied to a user and often disabled in locked-down orgs — prefer the SP.
- **Check (CLI):** `databricks current-user me` → returns your identity.
- **Check (no CLI):** `terraform plan` → authenticates and refreshes; a bad
  credential fails with a clear auth error rather than a resource diff.
- **Pass:** identity resolves / `plan` authenticates without an auth error.
