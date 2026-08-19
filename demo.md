# demo — deploy simple-demo end to end

Copy-paste sequence to stand up the full deployment (project + endpoint + UC
catalog) from a terminal, deploying as **your user** (`lakebase-sandbox`), which
has `CREATE CATALOG` so the catalog step won't block.

> If project + endpoint were already created by the automation SP (e.g. a prior
> test), Phase 1 tears them down first so you get a clean single-owner deploy.

## Full deploy

```bash
cd ~/simple-demo

# ── Phase 1: tear down any SP-created test resources (clean slate) ────────────
source ./env.sh                    # SP creds; env.sh also unsets profile/token
terraform destroy -auto-approve    # removes project+endpoint; purge_on_delete=true frees the slug

# ── Phase 2: switch to YOUR user identity (has CREATE CATALOG) ────────────────
unset DATABRICKS_HOST DATABRICKS_CLIENT_ID DATABRICKS_CLIENT_SECRET DATABRICKS_TOKEN
databricks auth login --profile lakebase-sandbox   # <-- interactive browser sign-in
export DATABRICKS_CONFIG_PROFILE=lakebase-sandbox
databricks auth describe           # sanity: Host = https://adb-7405612026214718...

# ── Phase 3: full deploy (project + endpoint + UC catalog) ────────────────────
terraform plan                     # review: 3 to add
terraform apply                    # type: yes   (or add -auto-approve)
terraform output                   # project_name, production_branch, prod_endpoint_host, uc_catalog_name

# ── Phase 4: tear down when done (stops billing) ─────────────────────────────
terraform destroy                  # type: yes
```

## Notes / watch-outs

- **Phase 2 order matters.** Unset the SP env vars *before* selecting the profile,
  or those explicit creds **shadow** the profile and you'll deploy as the SP again.
- **`databricks auth login`** is the only interactive step (opens a browser);
  needed because the `lakebase-sandbox` token may have expired.
- **Always-on cost:** the production primary endpoint does not scale to zero —
  it bills continuously until `terraform destroy`.
- **Known catalog risk:** `databricks_postgres_catalog` has failed before with
  *"Metastore storage root URL does not exist / Default Storage is enabled"* — a
  metastore-config issue, not permissions. If Phase 3 errors **only** on the
  catalog resource, deploy the rest and register the catalog from the UI:
  ```bash
  terraform apply -target=databricks_postgres_project.this \
                  -target=databricks_postgres_endpoint.prod_primary
  ```
  (The metastore storage-root config is an Admin-team item — see WORKSPACE requirements.)

## Alternative — deploy as the automation SP (CI-style)

Skip Phases 1–2. Have a **metastore admin** grant the SP once:

```sql
GRANT CREATE CATALOG ON METASTORE TO `45429f94-0d59-454b-b7f9-7f6814c60c7a`;
```

then:

```bash
cd ~/simple-demo
source ./env.sh          # SP creds
terraform apply          # keeps existing project+endpoint, adds the catalog
```
