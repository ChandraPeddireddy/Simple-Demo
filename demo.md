# Deploy simple-demo

Run these in order. **Open a new terminal first** (avoids stale credentials).

```bash
cd ~/simple-demo

# 1. Log in as yourself (opens a browser)
databricks auth login --profile lakebase-sandbox
export DATABRICKS_CONFIG_PROFILE=lakebase-sandbox

# 2. Deploy
terraform init
terraform apply          # review the plan, then type: yes

# 3. Show connection details (hand these to the app team)
terraform output

# 4. Tear down when finished
terraform destroy        # type: yes
```

That's it — step 2 creates the project, endpoint, and UC catalog.

---

**If `terraform apply` fails only on the catalog** (metastore storage error),
deploy everything else and add the catalog from the UI later:

```bash
terraform apply -target=databricks_postgres_project.this \
                -target=databricks_postgres_endpoint.prod_primary
```
