#!/usr/bin/env bash
# =============================================================================
# preflight.sh — deploy readiness checks for simple-demo. READ-ONLY.
#
# For each check it tries the happy path (Databricks CLI) and, on failure or if
# the CLI is absent, automatically falls back to the REST workaround — so it runs
# the same with or without the CLI. Nothing here creates resources.
#
# Inputs (flag > env var > interactive prompt). Provide auth ONE of two ways:
#   • CLI profile:  --profile <name>            (or $DATABRICKS_CONFIG_PROFILE)
#   • SP OAuth M2M: --host/--client-id/--client-secret
#                   (or $DATABRICKS_HOST/$DATABRICKS_CLIENT_ID/$DATABRICKS_CLIENT_SECRET)
#   • PAT:          --host --token              (or $DATABRICKS_HOST/$DATABRICKS_TOKEN)
#
# Other inputs:
#   --project-id <id>   project_id to deploy (default: simple-demo)
#   --principal  <p>    identity that will deploy (default: SP client id / current user)
#
# Usage:
#   ./preflight.sh --profile lakebase-sandbox
#   ./preflight.sh --host https://adb-x.azuredatabricks.net \
#                  --client-id <id> --client-secret <secret> --project-id simple-demo
#   source env.sh && ./preflight.sh          # picks up DATABRICKS_* from env
#
# Exit 0 = ready to deploy. Non-zero = at least one blocking check failed.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT
RC=0
c_pass=$'\033[32m'; c_warn=$'\033[33m'; c_fail=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
pass(){ echo "  ${c_pass}[PASS]${c_off} $*"; }
warn(){ echo "  ${c_warn}[WARN]${c_off} $*"; }
fail(){ echo "  ${c_fail}[FAIL]${c_off} $*"; RC=1; }
info(){ echo "  ${c_dim}$*${c_off}"; }
hdr(){ echo; echo "== $* =="; }

# --- inputs ------------------------------------------------------------------
PROFILE="${DATABRICKS_CONFIG_PROFILE:-}"
HOST="${DATABRICKS_HOST:-}"
CLIENT_ID="${DATABRICKS_CLIENT_ID:-}"
CLIENT_SECRET="${DATABRICKS_CLIENT_SECRET:-}"
PAT="${DATABRICKS_TOKEN:-}"
PROJECT_ID="${PROJECT_ID:-simple-demo}"
PRINCIPAL="${PRINCIPAL:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)       PROFILE="$2"; shift 2;;
    --host)          HOST="$2"; shift 2;;
    --client-id)     CLIENT_ID="$2"; shift 2;;
    --client-secret) CLIENT_SECRET="$2"; shift 2;;
    --token)         PAT="$2"; shift 2;;
    --project-id)    PROJECT_ID="$2"; shift 2;;
    --principal)     PRINCIPAL="$2"; shift 2;;
    -h|--help)       sed -n '2,32p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

have_cli(){ command -v databricks >/dev/null 2>&1; }
# api_get <path>: sets HTTP_CODE, writes response body to $BODY
api_get(){ HTTP_CODE=$(curl -s -o "$BODY" -w "%{http_code}" -H "Authorization: Bearer ${TOKEN}" "${HOST}$1"); }
jq_py(){ python3 -c "$1" 2>/dev/null; }

# --- resolve auth + a bearer TOKEN + HOST (interactive prompt if needed) ------
hdr "Auth resolution"
if [ -z "$PROFILE" ] && [ -z "$CLIENT_ID" ] && [ -z "$PAT" ]; then
  if [ -t 0 ]; then
    read -r -p "  Databricks host (https://adb-....azuredatabricks.net): " HOST
    read -r -p "  Auth: [1] SP client-id/secret  [2] CLI profile  [3] PAT : " a
    case "$a" in
      1) read -r -p "    client id: " CLIENT_ID; read -rs -p "    client secret: " CLIENT_SECRET; echo;;
      2) read -r -p "    profile name: " PROFILE;;
      3) read -rs -p "    PAT: " PAT; echo;;
    esac
  else
    fail "no auth provided (set --profile, or --host/--client-id/--client-secret, or --host/--token)"; exit 1
  fi
fi

TOKEN=""
if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ] && [ -n "$HOST" ]; then
  AUTH_MODE="SP M2M"
  TOKEN=$(curl -s -X POST "${HOST}/oidc/v1/token" --user "${CLIENT_ID}:${CLIENT_SECRET}" \
    --data 'grant_type=client_credentials&scope=all-apis' | jq_py "import json,sys;print(json.load(sys.stdin).get('access_token',''))")
  [ -z "$PRINCIPAL" ] && PRINCIPAL="$CLIENT_ID"
elif [ -n "$PAT" ] && [ -n "$HOST" ]; then
  AUTH_MODE="PAT"; TOKEN="$PAT"
elif [ -n "$PROFILE" ] && have_cli; then
  AUTH_MODE="CLI profile ($PROFILE)"
  [ -z "$HOST" ] && HOST=$(databricks auth profiles -o json 2>/dev/null | jq_py "import json,sys;print(next((p.get('host','') for p in json.load(sys.stdin).get('profiles',[]) if p.get('name')=='${PROFILE}'),''))")
  TOKEN=$(databricks auth token -p "$PROFILE" 2>/dev/null | jq_py "import json,sys;print(json.load(sys.stdin).get('access_token',''))")
fi
export DATABRICKS_CONFIG_PROFILE="${PROFILE:-}"; export DATABRICKS_HOST="${HOST:-}"

if [ -n "$TOKEN" ] && [ -n "$HOST" ]; then pass "auth mode: ${AUTH_MODE:-unknown}, host: ${HOST}"
else fail "could not obtain a bearer token/host — check credentials"; fi
CLI=false; have_cli && CLI=true

# --- 1. Terraform >= 1.9 ------------------------------------------------------
hdr "1. Terraform >= 1.9"
if command -v terraform >/dev/null 2>&1; then
  TV=$(terraform version -json 2>/dev/null | jq_py "import json,sys;print(json.load(sys.stdin)['terraform_version'])")
  if python3 -c "import sys;v=tuple(int(x) for x in '${TV:-0}'.split('.')[:2]);sys.exit(0 if v>=(1,9) else 1)"; then
    pass "terraform ${TV}"; else fail "terraform ${TV} < 1.9 — brew upgrade terraform"; fi
else fail "terraform not installed — brew install terraform"; fi

# --- 2. Databricks CLI (optional) --------------------------------------------
hdr "2. Databricks CLI (optional)"
if $CLI; then pass "databricks CLI $(databricks version 2>/dev/null) — happy paths enabled"
else warn "CLI absent — using REST fallbacks (deploy still works via env-var auth)"; fi

# --- 3. Authentication --------------------------------------------------------
hdr "3. Authentication resolves"
WHO=""
if $CLI; then WHO=$(databricks current-user me -o json 2>/dev/null | jq_py "import json,sys;d=json.load(sys.stdin);print(d.get('userName') or d.get('id'))"); fi
if [ -z "$WHO" ] && [ -n "$TOKEN" ]; then
  api_get "/api/2.0/preview/scim/v2/Me"
  [ "$HTTP_CODE" = "200" ] && WHO=$(jq_py "import json;print(json.load(open('$BODY')).get('userName',''))")
fi
if [ -n "$WHO" ]; then pass "authenticated as: ${WHO}"; [ -z "$PRINCIPAL" ] && PRINCIPAL="$WHO"
elif [ -n "$TOKEN" ]; then pass "token acquired (SP identity: ${PRINCIPAL:-unknown})"
else fail "authentication failed"; fi

# --- 4. Provider resolvable (terraform init) ---------------------------------
hdr "4. Provider >= 1.126.0 (terraform init)"
if terraform -chdir="$SCRIPT_DIR" init -backend=false -input=false >/dev/null 2>&1; then
  pass "provider resolved (terraform init OK)"
else
  fail "terraform init failed"
  info "workaround: public registry blocked? configure a filesystem/network provider"
  info "mirror in ~/.terraformrc (see PREVALIDATION.md #4), then re-run."
fi

# --- 5. Lakebase reachable (CLI -> REST) -------------------------------------
hdr "5. Lakebase reachable"
LB_OK=false
if $CLI && databricks postgres list-projects -o json >/dev/null 2>&1; then
  LB_OK=true; pass "Lakebase reachable (CLI)"
elif [ -n "$TOKEN" ]; then
  api_get "/api/2.0/postgres/projects"
  if [ "$HTTP_CODE" = "200" ]; then LB_OK=true; pass "Lakebase reachable (REST, HTTP 200)"
  else fail "Lakebase not reachable (HTTP ${HTTP_CODE}) — feature enabled? access? host?"; fi
else fail "cannot check Lakebase (no CLI and no token)"; fi

# --- 6. UC metastore attached (CLI -> REST) ----------------------------------
hdr "6. UC metastore attached"
MS_ID=""
if $CLI; then MS_ID=$(databricks metastores summary -o json 2>/dev/null | jq_py "import json,sys;print(json.load(sys.stdin).get('metastore_id',''))"); fi
if [ -z "$MS_ID" ] && [ -n "$TOKEN" ]; then
  api_get "/api/2.1/unity-catalog/metastore_summary"
  [ "$HTTP_CODE" = "200" ] && MS_ID=$(jq_py "import json;print(json.load(open('$BODY')).get('metastore_id',''))")
fi
if [ -n "$MS_ID" ]; then pass "metastore attached: ${MS_ID}"
else fail "no metastore attached — an account admin must assign one"; fi

# --- 7. CREATE CATALOG for the deploying principal (CLI -> REST) -------------
hdr "7. CREATE CATALOG on the metastore"
if [ -n "$MS_ID" ] && [ -n "$PRINCIPAL" ]; then
  CAT=""
  if $CLI; then
    CAT=$(databricks grants get-effective metastore "$MS_ID" --principal "$PRINCIPAL" -o json 2>/dev/null \
      | jq_py "import json,sys;d=json.load(sys.stdin);print('yes' if any(p['privilege']=='CREATE_CATALOG' for pa in d.get('privilege_assignments',[]) for p in pa['privileges']) else 'no')")
  fi
  if [ -z "$CAT" ] && [ -n "$TOKEN" ]; then
    api_get "/api/2.1/unity-catalog/effective-permissions/metastore/${MS_ID}?principal=${PRINCIPAL}"
    [ "$HTTP_CODE" = "200" ] && CAT=$(jq_py "import json;d=json.load(open('$BODY'));print('yes' if any(p['privilege']=='CREATE_CATALOG' for pa in d.get('privilege_assignments',[]) for p in pa['privileges']) else 'no')")
  fi
  if [ "$CAT" = "yes" ]; then pass "'${PRINCIPAL}' has CREATE_CATALOG"
  elif [ "$CAT" = "no" ]; then
    fail "'${PRINCIPAL}' lacks CREATE_CATALOG on the metastore"
    info "fix: metastore admin runs  GRANT CREATE CATALOG ON METASTORE TO \`${PRINCIPAL}\`;"
    info "or deploy project+endpoint only:  terraform apply -target=databricks_postgres_project.this -target=databricks_postgres_endpoint.prod_primary"
  else warn "could not determine CREATE_CATALOG (check principal/permissions API)"; fi
else warn "skipped — need metastore id (check 6) and a principal"; fi

# --- 8. project_id collision (CLI -> REST) -----------------------------------
hdr "8. project_id '${PROJECT_ID}' free"
PURGE=""; FOUND=""
if $CLI; then
  OUT=$(databricks postgres get-project "projects/${PROJECT_ID}" -o json 2>/dev/null)
  if [ -n "$OUT" ]; then FOUND=yes; PURGE=$(echo "$OUT" | jq_py "import json,sys;print(json.load(sys.stdin).get('purge_time','') or '')"); fi
fi
if [ -z "$FOUND" ] && [ -n "$TOKEN" ]; then
  api_get "/api/2.0/postgres/projects/${PROJECT_ID}"
  if [ "$HTTP_CODE" = "200" ]; then FOUND=yes; PURGE=$(jq_py "import json;print(json.load(open('$BODY')).get('purge_time','') or '')")
  elif [ "$HTTP_CODE" = "404" ]; then FOUND=no; fi
fi
if [ "$FOUND" = "no" ]; then pass "'${PROJECT_ID}' is free"
elif [ -n "$PURGE" ]; then fail "'${PROJECT_ID}' soft-deleted, slug reserved until ${PURGE} (wait or purge)"
elif [ "$FOUND" = "yes" ]; then fail "'${PROJECT_ID}' already exists (active) — pick a new id or manage it"
else warn "could not determine collision status for '${PROJECT_ID}'"; fi

# --- summary -----------------------------------------------------------------
hdr "Result"
if [ "$RC" -eq 0 ]; then echo "  ${c_pass}READY${c_off} — all blocking checks passed."
else echo "  ${c_fail}BLOCKED${c_off} — fix [FAIL] items above (see PREVALIDATION.md)."; fi
exit $RC
