# simple-demo

Minimal Terraform that stands up a **Lakebase** project for the app team and
hands off a **Unity Catalog** catalog. Deliberately small.

## What it creates

1. A **Lakebase project** (auto-provisions the `production` branch + a `primary`
   read-write endpoint).
2. The production **primary endpoint sized** to a sensible starting point
   (1–2 CU).
3. A **Unity Catalog catalog** registered for the project — the app team's
   governed entry point.

## What it deliberately does NOT do

- **No branching.** The **app** owns branching at runtime: each day it creates
  an ephemeral RW branch, opens it read-write, merges changes back to the
  lakehouse, drops the RW branch, and takes a fresh snapshot at end of day.
  Terraform only lays down the project + production branch; it must not manage
  branches or it will fight the app.
- **No HA / readable secondaries / autoscaling policy / suspension.** Only the
  instance size is set. Everything else is left at defaults so the app team can
  tune it **from the UI** once the configuration is finalized.

## Prerequisites

- Terraform >= 1.9, Databricks provider >= 1.126.0 (pinned).
- Databricks auth via env (`DATABRICKS_HOST` + `DATABRICKS_CLIENT_ID`/`SECRET`,
  or `DATABRICKS_CONFIG_PROFILE`).
- **`CREATE CATALOG` on the metastore** for whoever runs this (required to
  register the UC catalog).

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # edit as needed
terraform init
terraform plan
terraform apply
```

Outputs include the project name, production branch, endpoint host, and the UC
catalog name to hand to the app team.
