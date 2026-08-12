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

### Who can obtain these credentials

Two separate permission layers — obtaining a credential does **not** grant it the
ability to deploy (that's Checks 5–7).

| To do this | You need |
|------------|----------|
| Create the SP in the **account** | Account admin |
| Register the SP in the **workspace** | Workspace admin |
| Generate the SP's **OAuth secret** | Workspace/account admin, **or** `CAN_MANAGE` on that specific SP (delegated) |
| Generate a **PAT** | Token-based auth enabled for the workspace **and** the user holding the token-usage entitlement; the PAT inherits that user's permissions. Often disabled in locked-down orgs. |

A non-admin cannot self-create the SP secret — have a **workspace/account admin**
create the SP, generate its secret, grant it workspace/Lakebase access, and get a
**metastore admin** to grant `CREATE CATALOG`; then receive the `CLIENT_ID` +
`SECRET` over a secure channel.

> Azure note: this is the Databricks-managed SP OAuth-secret path. If your org
> mandates Microsoft Entra ID service principals, the secret is issued by Entra
> instead — confirm with your admin.

- **Alternative — Personal Access Token (PAT):** **Settings → Developer →
  Access tokens → Generate new token**, then:
  ```bash
  export DATABRICKS_HOST="https://adb-XXXXXXXX.azuredatabricks.net"
  export DATABRICKS_TOKEN="<pat>"
  ```
  PATs are tied to a user and often disabled in locked-down orgs — prefer the SP.
### Where these values go

The `export`s set credentials in the **shell environment** the provider reads —
they are not added to any `.tf` file. Pick one:

- **Local runs (recommended):** copy `env.sh.example` → `env.sh`, fill it in,
  then `source env.sh` before Terraform:
  ```bash
  cp env.sh.example env.sh   # edit with real values
  chmod 600 env.sh
  source env.sh
  terraform plan
  ```
  `env.sh` is gitignored, so the secret never gets committed (the secret-scan
  hook would block it anyway).
- **One-off:** paste the three `export` lines straight into your shell.
- **CI/CD (production):** store `CLIENT_ID`/`CLIENT_SECRET` in the pipeline's
  secret store (ideally backed by Azure Key Vault) and inject them as env vars
  at run time — never in the repo or logs.

> The `CLIENT_SECRET` is a live, **expiring** credential: keep it out of git,
> `*.tfvars`, Terraform state, and logs.

- **Check (CLI):** `databricks current-user me` → returns your identity.
- **Check (no CLI):** `terraform plan` → authenticates and refreshes; a bad
  credential fails with a clear auth error rather than a resource diff.
- **Pass:** identity resolves / `plan` authenticates without an auth error.

---

## 4. Databricks provider ≥ 1.126.0 resolvable (`terraform init`)

- **Validates:** `terraform init` can install the Databricks provider at the
  pinned version (`>= 1.126.0, < 2.0` in `versions.tf`), so `plan`/`apply` have
  the plugin.
- **Why ≥ 1.126.0:** first version exposing `databricks_postgres_project` /
  `_endpoint` / `_catalog`. On an older provider, `plan` fails with *"Invalid
  resource type."*

### Happy path (registry reachable)

```bash
terraform init
```
- **Pass:** *"Terraform has been successfully initialized!"* and a line like
  `Installed databricks/databricks v1.126.x`.
- `init` downloads the provider from **`registry.terraform.io`**.

### Workaround (public registry blocked — air-gapped / restricted)

If `init` fails with a registry/network error, point Terraform at an internal
source instead of the public registry:

- **Filesystem mirror** — on a connected machine:
  ```bash
  terraform providers mirror ./tf-mirror     # add -platform=linux_amd64 etc. for other OSes
  ```
  copy `./tf-mirror` to the restricted host, then in `~/.terraformrc`:
  ```hcl
  provider_installation {
    filesystem_mirror { path = "/path/to/tf-mirror" }
    direct { exclude = ["registry.terraform.io/*/*"] }
  }
  ```
- **Network mirror** — an internal registry (Artifactory / Nexus / TFE private
  registry) via a `network_mirror { url = "https://..." }` block in the same file.
- **Lock file:** commit `.terraform.lock.hcl` for reproducible versions; generate
  cross-platform hashes with
  `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64`.
- **Other failures:** stale cached provider → `terraform init -upgrade`; version
  conflict → check the `versions.tf` pin.

---

## 5. Lakebase (Postgres) enabled & reachable

- **Validates:** the workspace has **Lakebase (OLTP / Postgres)** enabled and the
  authenticated identity can reach its API. All three resources are
  `databricks_postgres_*`, so if the feature is off or unreachable, `apply` fails
  on the very first resource.

### Happy path (CLI)

```bash
databricks postgres list-projects        # --profile <p> if using a profile
```
- **Pass:** returns a list (empty `[]` is fine — just no projects yet), exit 0.

### No-CLI REST probe (verified)

Fully CLI-free — mint an M2M token, then hit the Lakebase API:

```bash
# 1) OAuth M2M token from the SP creds (client_credentials)
TOKEN=$(curl -s --request POST "${DATABRICKS_HOST}/oidc/v1/token" \
  --user "${DATABRICKS_CLIENT_ID}:${DATABRICKS_CLIENT_SECRET}" \
  --data 'grant_type=client_credentials&scope=all-apis' \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")

# 2) reachability probe — expect HTTP 200
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -H "Authorization: Bearer ${TOKEN}" \
  "${DATABRICKS_HOST}/api/2.0/postgres/projects"
```
- **Pass:** step 1 returns an `access_token`; step 2 prints `HTTP 200`.
- *(For a PAT instead of an SP, skip step 1 and use `Authorization: Bearer $DATABRICKS_TOKEN`.)*

### If it fails

- **`FEATURE_DISABLED` / 404 / not found:** Lakebase isn't enabled for this
  workspace — a **workspace/account admin** enables it (Azure `eastus2` is GA);
  confirm the region supports Lakebase.
- **`401`/`PERMISSION_DENIED`:** bad token (recheck creds) or the identity lacks
  workspace access — grant it.
- **Wrong host:** confirm `DATABRICKS_HOST` points at the intended workspace.
- Otherwise reachability also surfaces at `apply` time: the
  `databricks_postgres_project` resource is created first and fails fast.
