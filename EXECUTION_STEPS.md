# Execution Steps — `simple-demo`

A step-by-step runbook for deploying this Terraform in your Databricks
workspace. Follow the steps in order. Deep detail for any check lives in
[`PREVALIDATION.md`](./PREVALIDATION.md); what the module does and why is in
[`README.md`](./README.md).

**What you'll end up with:** a Lakebase (Postgres) project with a production
branch, a right-sized always-on endpoint, and a Unity Catalog catalog to hand to
the app team. (The app manages day-to-day branching itself; HA/autoscaling are
tuned later from the UI.)

---

## Step 0 — Collect the details you'll need

Gather these before you start (fill in the blanks):

| Item | Example | Where it comes from |
|------|---------|---------------------|
| Workspace URL (`HOST`) | `https://adb-XXXX.azuredatabricks.net` | browser address bar of your workspace |
| Auth method | SP OAuth M2M *(recommended)* / CLI profile / PAT | pick one — see "Choosing an auth method" below |
| SP application id (`CLIENT_ID`) | `xxxxxxxx-xxxx-…` | Settings → Identity and access → Service principals |
| SP OAuth secret (`CLIENT_SECRET`) | *(secret)* | the SP → Secrets → Generate secret (shown once) |
| Deploying principal | SP app id, or your user email | the identity Terraform runs as |
| `project_id` | `simple-demo` | you choose (immutable; becomes the slug) |
| Instance size | `1`–`2` CU | sensible start; tune later in UI |
| UC catalog name | `simple_demo` | you choose |
| Metastore admin contact | *(a person)* | needed to grant `CREATE CATALOG` (Step 5/8) |

> The **secret** is a live, expiring credential — keep it out of git, `*.tfvars`,
> and logs. See [`PREVALIDATION.md` §3](./PREVALIDATION.md) for exactly how to
> obtain each value and **who** can generate it.

### Choosing an auth method

Terraform needs a credential to talk to your workspace. Pick **one** — they're
equivalent for deploying; the difference is how the credential is issued.

| Method | Best when | What you provide | Databricks CLI needed? | Expires? |
|--------|-----------|------------------|------------------------|----------|
| **SP OAuth M2M** *(recommended)* | Automation/CI, locked-down networks, or no CLI allowed. This is the standard enterprise choice. | `HOST` + `CLIENT_ID` + `CLIENT_SECRET` (the SP's OAuth secret) | **No** — the provider mints its own token | Secret has an expiry; rotate it |
| **CLI profile** | Interactive local use where you can install the CLI and sign in via browser. | Run `databricks auth login --host <url> --profile <name>` (interactive) | **Yes** | Token auto-refreshes |
| **PAT** | Quick one-off manual test. Frequently **disabled** in locked-down orgs. | `HOST` + a personal access token | No | Yes; tied to your user |

- **Recommendation:** use **SP OAuth M2M** for anything shared or repeatable — it
  works without the CLI (pure REST/provider auth), suits restricted networks, and
  isn't tied to a person.
- **Regardless of method**, the identity still needs the actual *deploy*
  permissions (Lakebase access; and `CREATE CATALOG` for the catalog) — getting a
  credential ≠ having those rights. See [`PREVALIDATION.md` §3 and §7](./PREVALIDATION.md).

---

## Step 1 — Verify Git access & get the code

```bash
git clone https://github.com/ChandraPeddireddy/Simple-Demo.git
cd Simple-Demo
ls    # expect: main.tf variables.tf outputs.tf versions.tf
      #         terraform.tfvars.example env.sh.example preflight.sh
      #         PREVALIDATION.md EXECUTION_STEPS.md README.md
```
- **Expected:** the files above are present.
- **If it fails:** confirm you have read access to the repo (ask the repo owner
  to add you) and that your Git credentials/SSH are set up.

---

## Step 2 — Install tooling

- **Required:** Terraform ≥ 1.9.
  ```bash
  terraform version      # expect v1.9.x or newer
  ```
- **Optional:** the Databricks CLI (nice for verification, not required —
  everything works over REST without it).
- **Optional:** `psql` (only to test a live DB connection later).

If Terraform is missing/old: `brew install terraform` (or your platform's method).

---

## Step 3 — Configure credentials

Do **Option A** or **Option B** (matching your Step 0 choice), not both.

### Option A — SP OAuth M2M (recommended, no CLI)

```bash
cp env.sh.example env.sh          # env.sh is gitignored — never commit it
chmod 600 env.sh
# edit env.sh:  DATABRICKS_HOST, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET
source env.sh
echo "$DATABRICKS_HOST"           # sanity check — prints your workspace URL
```
- Then in later steps use: `./preflight.sh --project-id <project-id> --principal "$DATABRICKS_CLIENT_ID"`.
- **Auth-precedence gotcha:** a `DATABRICKS_CONFIG_PROFILE` (or `DATABRICKS_TOKEN`)
  left set in your shell **shadows** these SP creds and silently authenticates to
  the wrong workspace (you'll see `profile=<name>` and an unexpected host in errors).
  `env.sh` now `unset`s both on `source`; if you run Terraform without sourcing
  `env.sh`, clear them yourself first (`unset DATABRICKS_CONFIG_PROFILE`).

### Option B — CLI profile (requires the Databricks CLI)

```bash
# 1. Install the CLI (once)
brew tap databricks/tap && brew install databricks     # or your platform's method

# 2a. USER profile — interactive browser sign-in:
databricks auth login --host https://adb-XXXXXXXX.azuredatabricks.net --profile <profile>

# 2b. OR a SERVICE-PRINCIPAL profile — add a block to ~/.databrickscfg (no browser):
#   [<profile>]
#   host          = https://adb-XXXXXXXX.azuredatabricks.net
#   client_id     = <sp-application-id>
#   client_secret = <sp-oauth-secret>

# 3. Verify the profile works
databricks auth profiles          # your <profile> should show Valid = YES
databricks current-user me        # confirms the identity
```
- Then in later steps use `--profile <profile>` instead of `source env.sh`
  (e.g. `./preflight.sh --profile <profile> --project-id <project-id>`).

---

## Step 4 — Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# edit: project_id, prod_min_cu/prod_max_cu, uc_catalog_id
```
- Keep `project_id` unique (it's immutable). Defaults are a sensible start.

---

## Step 5 — Run pre-validation (do this before anything else)

One command checks all 8 prerequisites (tries CLI, falls back to REST):

```bash
# SP M2M (after `source env.sh`):
./preflight.sh --project-id <project-id> --principal "$DATABRICKS_CLIENT_ID"

# or CLI profile:
./preflight.sh --profile <profile> --project-id <project-id>
```
- `<project-id>` = the value you set in `terraform.tfvars` (Step 4); `<profile>`
  = the CLI profile name from Step 3 Option B.
- **Expected:** ends with `READY — all blocking checks passed.`
- **If it says `BLOCKED`:** fix each `[FAIL]` (the script prints the fix). The
  most common one is **Check #7 `CREATE CATALOG`** — see Step 8. Full guidance
  per check: [`PREVALIDATION.md`](./PREVALIDATION.md).

---

## Step 6 — Initialize Terraform

```bash
terraform init
```
- **Expected:** *"Terraform has been successfully initialized!"*
- **If the public registry is blocked:** configure a provider mirror — see
  [`PREVALIDATION.md` §4](./PREVALIDATION.md).

---

## Step 7 — Review the plan

```bash
terraform plan
```
- **Expected:** `Plan: 3 to add, 0 to change, 0 to destroy`
  (project, production endpoint, UC catalog). Review the endpoint size and
  catalog name.

---

## Step 8 — Apply

**If pre-validation was fully green:**
```bash
terraform apply        # review, then type: yes
```

**If Check #7 (`CREATE CATALOG`) is still blocked** — deploy everything *except*
the catalog now, add it once the grant is in place:
```bash
terraform apply -target=databricks_postgres_project.this \
                -target=databricks_postgres_endpoint.prod_primary
```
Then have a **metastore admin** run:
```sql
GRANT CREATE CATALOG ON METASTORE TO `<your-principal>`;
```
and finish with a plain `terraform apply` to add the catalog.

> **Cost note:** the production endpoint is **always-on** (no scale-to-zero) —
> it bills continuously until you `terraform destroy`.

---

## Step 9 — Verify

```bash
terraform output          # project_name, production_branch, prod_endpoint_host, uc_catalog_name
```

**Optional live DB check** (needs `psql`). You need three things: the host, a
short-lived Postgres token, and the connecting principal.

```bash
EP="projects/$(terraform output -raw project_name | sed 's#projects/##')/branches/production/endpoints/primary"
PGHOST="$(terraform output -raw prod_endpoint_host)"

# --- token, CLI happy path ---
PGPASSWORD="$(databricks postgres generate-database-credential "$EP" -o json \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")"

# --- token, no-CLI (Lakebase REST; reuse HOST + a bearer TOKEN as in preflight) ---
# PGPASSWORD="$(curl -s -X POST -H "Authorization: Bearer ${TOKEN}" \
#   "${DATABRICKS_HOST}/api/2.0/postgres/${EP#projects/}/credentials" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')"

# --- connect (user = your principal: SP app id or user email) ---
PGPASSWORD="$PGPASSWORD" psql "host=$PGHOST user=<principal> dbname=databricks_postgres sslmode=require" \
  -c "select current_user, version();"
```
- **Expected:** outputs populated; `psql` returns your identity and a
  PostgreSQL 17.x version string.

---

## Step 10 — Hand off to the app team

Give the app team:
- **UC catalog name** (`terraform output uc_catalog_name`) — their governed entry point.
- **Production branch** (`terraform output production_branch`) and **endpoint host**.
- A reminder that **they own branching** (daily RW branch → merge to lakehouse →
  drop → snapshot) and can tune **HA / autoscaling / read replicas from the UI**.

---

## Step 11 — Teardown (when finished)

```bash
terraform destroy         # review, then type: yes
```
- Stops billing.
- **Soft vs hard delete** is controlled by `purge_on_delete` (default `true` for
  now, for easy dev/demo iteration — **set to `false` for production**):
  - `false` → **soft delete**: the `project_id` slug stays **reserved ~7 days**
    (re-deploying the same id within the window is fine — it reuses the slug).
  - `true` → **hard delete**: frees the slug **immediately**.
  To keep the slug on destroy (recommended for prod), set `purge_on_delete = false`
  in `terraform.tfvars`, or inline: `terraform destroy -var purge_on_delete=false`.

---

## Appendix — all commands, in order (copy-paste)

SP OAuth M2M path (works without the Databricks CLI). Replace the `<...>` values.

```bash
# --- Step 1: get the code ---
git clone https://github.com/ChandraPeddireddy/Simple-Demo.git
cd Simple-Demo

# --- Step 2: verify tooling ---
terraform version                      # need >= 1.9

# --- Step 3: credentials ---
cp env.sh.example env.sh
chmod 600 env.sh
# edit env.sh: DATABRICKS_HOST, DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET
source env.sh
echo "$DATABRICKS_HOST"                # sanity check

# --- Step 4: variables ---
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project_id, prod_min_cu/prod_max_cu, uc_catalog_id

# --- Step 5: pre-validation (all 8 checks) ---
./preflight.sh --project-id <project-id> --principal "$DATABRICKS_CLIENT_ID"
# fix any [FAIL]; must end with: READY

# --- Step 6-8: deploy ---
terraform init
terraform plan
terraform apply                        # type: yes
#   ...if CREATE CATALOG not yet granted, deploy project+endpoint only:
#   terraform apply -target=databricks_postgres_project.this \
#                   -target=databricks_postgres_endpoint.prod_primary
#   then (metastore admin) GRANT CREATE CATALOG ON METASTORE TO `<principal>`;  and re-run: terraform apply

# --- Step 9: verify ---
terraform output

# --- Step 11: teardown (when finished) ---
terraform destroy                      # type: yes
```

CLI-profile path differs only in Steps 3 and 5:
```bash
databricks auth login --host <url> --profile <profile>          # Step 3 (instead of env.sh)
./preflight.sh --profile <profile> --project-id <project-id>    # Step 5
```

---

## Quick reference

| Need | File |
|------|------|
| Per-check detail, fixes, permissions | [`PREVALIDATION.md`](./PREVALIDATION.md) |
| Automated readiness check | `./preflight.sh` |
| What the module does / design intent | [`README.md`](./README.md) |
| Credential template | `env.sh.example` |
| Variable template | `terraform.tfvars.example` |
