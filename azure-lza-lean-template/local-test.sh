#!/bin/bash
# =============================================================
# local-test.sh
# Run terraform plan/apply/destroy locally using az login
# Automatically passes terraform.tfvars + local.auto.tfvars
#
# Usage:
#   ./local-test.sh                          # plan all layers
#   ./local-test.sh shared/04-hub            # plan one layer
#   ./local-test.sh shared/04-hub apply      # apply one layer
#   ./local-test.sh dev/05-workload destroy  # destroy one layer
#   ./local-test.sh all apply                # apply all in order
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_SUB="YOUR_PLATFORM_SUBSCRIPTION_ID"
NONPROD_SUB="YOUR_NONPROD_SUBSCRIPTION_ID"
PROD_SUB="YOUR_PROD_SUBSCRIPTION_ID"
TENANT_ID="YOUR_TENANT_ID"

# ── Auth ─────────────────────────────────────────────────────
# ARM_SUBSCRIPTION_ID stays as platform sub throughout
# Workload layers use var.workload_subscription_id in providers.tf
export ARM_USE_OIDC=false
export ARM_USE_AZURE_CLI_AUTH=true
export ARM_TENANT_ID="$TENANT_ID"
export ARM_SUBSCRIPTION_ID="$PLATFORM_SUB"

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
sep()  { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Prereq check ─────────────────────────────────────────────
check_prereqs() {
  command -v terraform >/dev/null 2>&1 || err "terraform not installed"
  command -v az >/dev/null 2>&1        || err "azure-cli not installed"

  TF_VER=$(terraform version -json 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('terraform_version','unknown'))")
  log "Terraform: $TF_VER"

  if ! az account show --query id -o tsv > /dev/null 2>&1; then
    err "Not logged in. Run: az login"
  fi

  ACCT=$(az account show --query "{name:name,id:id}" -o json)
  ACCT_NAME=$(echo "$ACCT" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  ok "Logged in: $ACCT_NAME"
  ok "ARM_SUBSCRIPTION_ID: $ARM_SUBSCRIPTION_ID (platform — workload sub set in providers.tf)"
}

# ── Run one layer ─────────────────────────────────────────────
run_layer() {
  local LAYER="$1"
  local ACTION="${2:-plan}"
  local FULL="$SCRIPT_DIR/environments/$LAYER"

  [ -d "$FULL" ] || err "Layer not found: environments/$LAYER"

  sep
  log "Layer: ${BOLD}$LAYER${NC}  Action: ${BOLD}$ACTION${NC}"

  pushd "$FULL" > /dev/null

  # Build -var-file args
  VARFILES=()
  if [ -f "terraform.tfvars" ]; then
    VARFILES+=("-var-file=terraform.tfvars")
    ok "Using terraform.tfvars"
  fi
  if [ -f "local.auto.tfvars" ]; then
    VARFILES+=("-var-file=local.auto.tfvars")
    ok "Using local.auto.tfvars"
  fi
  if [ -f "local.tfvars" ]; then
    VARFILES+=("-var-file=local.tfvars")
    ok "Using local.tfvars"
  fi

  # Warn if secret tfvars missing for layers that need them
  case "$LAYER" in
    shared/04-hub|dev/05-workload|prod/05-workload)
      if [ ! -f "local.auto.tfvars" ] && [ ! -f "local.tfvars" ]; then
        warn "No local.auto.tfvars found — copy from .example file and fill in values"
      fi
      ;;
  esac

  # Init
  log "terraform init..."
  terraform init -reconfigure -input=false -no-color \
    > /tmp/tf-init.log 2>&1 \
    && ok "init complete" \
    || { cat /tmp/tf-init.log; err "init failed for $LAYER"; }

  # Validate
  terraform validate -no-color > /dev/null \
    && ok "validate passed" \
    || err "validate failed for $LAYER"

  case "$ACTION" in
    plan)
      log "terraform plan..."
      terraform plan \
        "${VARFILES[@]}" \
        -out=local.tfplan \
        -detailed-exitcode \
        -no-color 2>&1 | tee /tmp/tf-plan.log || true

      EXIT_CODE=${PIPESTATUS[0]}
      case $EXIT_CODE in
        0) ok "No changes" ;;
        2) warn "Changes detected — review above" ;;
        1) popd > /dev/null; err "Plan failed for $LAYER" ;;
      esac
      ;;

    apply)
      if [ ! -f "local.tfplan" ]; then
        warn "No local.tfplan found — running plan first..."
        terraform plan "${VARFILES[@]}" -out=local.tfplan -no-color
      fi
      log "terraform apply..."
      terraform apply local.tfplan -no-color \
        && ok "Apply complete: $LAYER" \
        || { popd > /dev/null; err "Apply failed for $LAYER"; }
      rm -f local.tfplan
      ;;

    plan-and-apply)
      log "terraform plan..."
      terraform plan "${VARFILES[@]}" -out=local.tfplan -no-color
      log "terraform apply..."
      terraform apply local.tfplan -no-color \
        && ok "Apply complete: $LAYER" \
        || { popd > /dev/null; err "Apply failed for $LAYER"; }
      rm -f local.tfplan
      ;;

    destroy)
      log "terraform destroy..."
      echo ""
      read -rp "  Type layer name to confirm destroy [${LAYER}]: " CONFIRM
      if [ "$CONFIRM" = "$LAYER" ]; then
        terraform destroy "${VARFILES[@]}" -auto-approve -no-color \
          && ok "Destroy complete: $LAYER" \
          || { popd > /dev/null; err "Destroy failed for $LAYER"; }
      else
        warn "Aborted — confirmation did not match"
      fi
      ;;

    *)
      popd > /dev/null
      err "Unknown action: $ACTION. Use plan | apply | plan-and-apply | destroy"
      ;;
  esac

  popd > /dev/null
}

# ── Run all layers in pipeline order ─────────────────────────
run_all() {
  local ACTION="${1:-plan}"

  local LAYERS=(
    "shared/03-management"
    "shared/04-hub"
    "dev/01-management-groups"
    "dev/02-policy"
    "dev/05-workload"
    "shared/05-avnm"
  )

  if [ "$ACTION" = "destroy" ]; then
    LAYERS=(
      "shared/05-avnm"
      "dev/05-workload"
      "dev/02-policy"
      "dev/01-management-groups"
      "shared/04-hub"
      "shared/03-management"
    )
  fi

  TOTAL=${#LAYERS[@]}
  log "Running $TOTAL layers — action: ${BOLD}$ACTION${NC}"
  echo ""

  FAILED=()
  for i in "${!LAYERS[@]}"; do
    LAYER="${LAYERS[$i]}"
    NUM=$((i + 1))
    log "[$NUM/$TOTAL] $LAYER"
    run_layer "$LAYER" "$ACTION" || FAILED+=("$LAYER")
    echo ""
  done

  sep
  if [ ${#FAILED[@]} -eq 0 ]; then
    ok "All $TOTAL layers completed successfully"
  else
    for F in "${FAILED[@]}"; do echo -e "  ${RED}✗${NC} $F"; done
    err "One or more layers failed"
  fi
}

# ── Main ──────────────────────────────────────────────────────
check_prereqs
echo ""

case "${1:-}" in
  "")        run_all plan ;;
  "all")     run_all "${2:-plan}" ;;
  *)         run_layer "$1" "${2:-plan}" ;;
esac
