# simple-demo

Minimal Terraform that stands up a **Lakebase** project for the app team and
hands off a **Unity Catalog** catalog. Deliberately small — it lays the
foundation and gets out of the app team's way.

---

## What it creates

1. A **Lakebase project** — `databricks_postgres_project` (auto-provisions the
   `production` branch + a `primary` read-write endpoint).
2. The production **primary endpoint, sized** to a sensible starting point
   (1–2 CU) — `databricks_postgres_endpoint`.
3. A **Unity Catalog catalog** registered for the project —
   `databricks_postgres_catalog`, the app team's governed entry point.

## What it deliberately does NOT do

- **No branching.** The **app** owns branching at runtime: each day it creates
  an ephemeral RW branch, opens it read-write, merges changes back to the
  lakehouse, drops the RW branch, and takes a fresh snapshot at end of day.
  Terraform only lays down the project + production branch; if it managed
  branches it would fight the app.
- **No HA / readable secondaries / autoscaling policy / suspension.** Only the
  instance size is set. Everything else stays at defaults so the app team can
  tune it **from the UI** once the configuration is finalized.

---

## Repository walkthrough (what each file carries)

### Terraform core

| File | What it carries | Values to look out for |
|---|---|---|
| **`versions.tf`** | Version constraints + the `databricks` provider block. | Terraform **≥ 1.9** (needed for cross-variable validation); provider **≥ 1.126.0, < 2.0** (first version exposing the `postgres_*` resources). These are **constraints, not exact pins** — `.terraform.lock.hcl` (which pins the resolved version) is gitignored, so commit it if the team needs byte-identical provider installs. Auth is **env-based — nothing is hardcoded**. |
| **`main.tf`** | The 3 resources: project → sized primary endpoint → UC catalog. | `endpoint.replace_existing = true` **adopts** the auto-created `primary` (doesn't make a second one). `catalog.create_database_if_missing = false`. The catalog resource **requires `CREATE CATALOG` on the metastore**. No branch/HA resources — by design. |
| **`variables.tf`** | All inputs, each with a validation rule. | See the **"Values to review"** table below — this is the file to read line-by-line in the session. |
| **`outputs.tf`** | What you hand to the app team after apply. | `project_name`, `production_branch`, `prod_endpoint_host` (RW connection host), `uc_catalog_name`. |

### Configuration & repo hygiene

The two `*.example` files are **templates you copy** to their real names (the
copies are gitignored). `.gitignore` is the committed file that enforces that.

| File | What it carries | Values to look out for |
|---|---|---|
| **`terraform.tfvars.example`** | Template of input values. Copy to **`terraform.tfvars`** (gitignored). | This is where you set `project_id`, sizing, and the UC catalog name. Note `purge_on_delete = true` here — **flip to `false` for prod**. |
| **`env.sh.example`** | Credential template (host + SP OAuth **or** PAT). Copy to **`env.sh`** (gitignored), `chmod 600`, then `source`. | The `CLIENT_SECRET` is a **live, expiring credential** — never commit it, never put it in tfvars/state/logs. For CI, inject from the pipeline secret store, not a file. |
| **`.gitignore`** | Committed. Keeps secrets and state out of git. | Ignores `env.sh`, `*.tfvars`, all `*.tfstate*`, `.terraform/`, and `.terraform.lock.hcl`. **State is local** here (POC) — for shared/team use, move to a **remote backend**. |

### Readiness & runbook docs

| File | What it carries | Values to look out for |
|---|---|---|
| **`preflight.sh`** | **Read-only** 8-check "ready to deploy?" script. Tries the Databricks CLI, auto-falls back to REST if the CLI is absent. Exit 0 = ready. | Run it **before every deploy**. Checks: Terraform ≥1.9, CLI (optional), auth, provider resolves, Lakebase reachable, metastore attached, **`CREATE CATALOG` for the deploying principal**, and **`project_id` collision** (active or soft-deleted/slug-reserved). |
| **`PREVALIDATION.md`** | The narrative behind each preflight check — how to get each value from the workspace, who can get credentials, and workarounds (e.g. blocked provider registry). | Reference doc for when a check **fails** and you need the fix. |
| **`EXECUTION_STEPS.md`** | The full **step-by-step customer runbook** (Steps 0 → 11: setup, deploy, verify, hand-off, teardown). | The authoritative deploy guide — hand this to whoever runs the deploy. |
| **`README.md`** | This overview. | Start here; go to `EXECUTION_STEPS.md` to actually deploy. |

---

## Values to review before you deploy (`variables.tf` / `terraform.tfvars`)

| Variable | Default | Watch out for |
|---|---|---|
| `project_id` | `simple-demo` | **Immutable** — changing it **recreates** the project. 3–63 chars, lowercase alphanumeric/hyphens, no leading/trailing hyphen. |
| `project_display_name` | `Simple Demo` | Cosmetic only (shown in the UI). |
| `pg_version` | `17` | Must be one of 14/15/16/17. |
| `purge_on_delete` | **`true`** | **`true` = hard delete on destroy** (frees the `project_id` slug immediately). Kept `true` for easy dev/demo iteration. **Set `false` for production** so a destroy can't immediately and irreversibly drop the project (7-day soft-delete recovery window). |
| `prod_min_cu` / `prod_max_cu` | `1` / `2` | Each 0.5–32 CU; `max ≥ min`; the **spread (max − min) must be ≤ 16 CU**. Starting size only — the app team tunes autoscaling/HA/suspension from the UI. |
| `uc_catalog_id` | `simple_demo` | Letters/digits/underscores only. This is the catalog name handed to the app team. |
| `uc_catalog_postgres_database` | `databricks_postgres` | The Postgres DB the catalog exposes (Lakebase default). |

**Two things to call out in the session:**
- **`CREATE CATALOG` on the metastore** is required for whoever runs this (SP or user). Without it, the project + endpoint apply but the **catalog step fails** — preflight check #7 catches this. Fallback: deploy just the project + endpoint with
  `terraform apply -target=databricks_postgres_project.this -target=databricks_postgres_endpoint.prod_primary`.
- The production **primary endpoint is always-on** (no scale-to-zero is set here) → **continuous compute cost** until you `terraform destroy`.

---

## How to deploy

Full runbook: **`EXECUTION_STEPS.md`**. Quickstart (happy path):

```bash
# 0. Get the code
git clone https://github.com/ChandraPeddireddy/Simple-Demo.git && cd Simple-Demo

# 1. Credentials — pick ONE
cp env.sh.example env.sh    # fill in host + SP client id/secret, then:
chmod 600 env.sh && source env.sh
#   ...or use a Databricks CLI profile (DATABRICKS_CONFIG_PROFILE) instead.

# 2. Readiness check (read-only — creates nothing)
./preflight.sh              # picks up DATABRICKS_* from env; must print READY

# 3. Inputs
cp terraform.tfvars.example terraform.tfvars   # edit project_id, sizing, catalog

# 4. Deploy
terraform init
terraform plan              # review: 3 resources to add
terraform apply

# 5. Hand-off values
terraform output            # project_name, production_branch, prod_endpoint_host, uc_catalog_name
```

### Prerequisites

- Terraform **≥ 1.9**, Databricks provider **≥ 1.126.0** (constrained in `versions.tf`).
- Databricks auth via env (`DATABRICKS_HOST` + `DATABRICKS_CLIENT_ID`/`SECRET`,
  or `DATABRICKS_CONFIG_PROFILE`).
- **`CREATE CATALOG` on the metastore** for the deploying identity.

### Teardown

```bash
terraform destroy
```

With `purge_on_delete = true` (current default) this **hard-deletes** and frees
the `project_id` slug immediately. To keep the slug reserved (recommended for
prod), set `purge_on_delete = false` first, or run
`terraform destroy -var purge_on_delete=false`.
