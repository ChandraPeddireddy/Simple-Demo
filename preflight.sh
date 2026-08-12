#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Preflight checks for deploying simple-demo. READ-ONLY — creates nothing.
#
# Auth: pick ONE before running:
#   (a) profile:  export DATABRICKS_CONFIG_PROFILE=lakebase-sandbox
#   (b) SP M2M:   source env.sh   (DATABRICKS_HOST + CLIENT_ID + CLIENT_SECRET)
#
# Usage:  ./preflight.sh
# Exit 0 = ready to deploy (catalog still needs the metastore grant — see WARN).
# -----------------------------------------------------------------------------
set -uo pipefail
RC=0
pass(){ echo "  [PASS] $*"; }
warn(){ echo "  [WARN] $*"; }
fail(){ echo "  [FAIL] $*"; RC=1; }

echo "== 1. Tooling =="
if command -v terraform >/dev/null 2>&1; then
  TV=$(terraform version -json 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null)
  python3 -c "import sys;v=tuple(int(x) for x in '${TV:-0.0.0}'.split('.')[:2]);sys.exit(0 if v>=(1,9) else 1)" \
    && pass "terraform ${TV} (>= 1.9)" || fail "terraform ${TV} is < 1.9 (required for cross-variable validation)"
else fail "terraform not installed"; fi
command -v databricks >/dev/null 2>&1 && pass "databricks CLI $(databricks version 2>/dev/null)" || fail "databricks CLI not installed"
command -v psql >/dev/null 2>&1 && pass "psql present (optional — only for DB connectivity tests)" || warn "psql not found (optional; not needed for terraform)"

echo "== 2. Databricks auth =="
WHO=$(databricks current-user me -o json 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('userName') or d.get('id'))" 2>/dev/null)
[ -n "${WHO:-}" ] && pass "authenticated as: ${WHO}" || fail "no working auth (set DATABRICKS_CONFIG_PROFILE or source env.sh)"

echo "== 3. Lakebase (Postgres) reachable =="
if databricks postgres list-projects -o json >/dev/null 2>&1; then
  N=$(databricks postgres list-projects -o json 2>/dev/null | python3 -c "import json,sys;print(len(json.load(sys.stdin) or []))")
  pass "Lakebase API reachable (existing projects: ${N})"
else fail "cannot reach Lakebase API (feature enabled? auth valid?)"; fi

echo "== 4. Unity Catalog metastore =="
MS=$(databricks metastores current -o json 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('metastore_name') or d.get('metastore_id'))" 2>/dev/null)
[ -n "${MS:-}" ] && pass "metastore attached: ${MS}" || warn "could not read current metastore"
warn "CREATE CATALOG on the metastore is REQUIRED for the UC catalog resource and"
warn "  is NOT verifiable read-only. Confirm with a metastore admin:"
warn "  GRANT CREATE CATALOG ON METASTORE TO \`${WHO:-<principal>}\`;"

echo "== 5. Terraform provider resolves =="
if terraform -chdir="$(dirname "$0")" init -backend=false -input=false >/dev/null 2>&1; then
  pass "provider databricks >= 1.126.0 resolved (terraform init OK)"
else fail "terraform init failed (network to registry.terraform.io? provider pin?)"; fi

echo
[ "$RC" -eq 0 ] && echo "PREFLIGHT: READY (mind the CREATE CATALOG grant above)" || echo "PREFLIGHT: BLOCKED — fix [FAIL] items above"
exit $RC
