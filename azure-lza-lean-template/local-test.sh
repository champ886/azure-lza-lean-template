#!/bin/bash
# =============================================================
# local-test.sh
# Run terraform plan/apply/destroy locally using az login
# Automatically passes terraform.tfvars + local.tfvars (if present)
#
# Usage:
#   ./local-test.sh                          # plan all layers in order
#   ./local-test.sh shared/04-hub            # plan one layer
#   ./local-test.sh shared/04-hub apply      # apply one layer
#   ./local-test.sh dev/05-workload destroy  # destroy one layer
#   ./local-test.sh all apply                # apply all in order
# =============================================================

set -euo pipefail

PLATFORM_SUB="YOUR_PLATFORM_SUBSCRIPTION_ID"
NONPROD_SUB="YOUR_NONPROD_SUBSCRIPTION_ID"
PROD_SUB="YOUR_PROD_SUBSCRIPTION_ID"

# ── Auth — az login token, no OIDC needed locally ────────────
export ARM_USE_OIDC=false
export ARM_USE_AZURE_CLI_AUTH=true
export ARM_TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "${RED}✗${NC} $1"; exit 1; }
sep()  { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Prereq check ─────────────────────────────────────────────
check_prereqs() {
  command -v terraform >/dev/null 2>&1 || err "terraform not installed"
  command -v az >/dev/null 2>&1        || err "azure-cli not installed"

  TF_VER=$(terraform version -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('terraform_version','unknown'))")
  AZ_VER=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
  log "Terraform: $TF_VER  |  Azure CLI: $AZ_VER"

  if ! az account show --query id -o tsv > /dev/null 2>&1; then
    err "Not logged in. Run: az login && az account set --subscription $PLATFORM_SUB"
  fi

  CURRENT=$(az account show --query "{name:name,id:id}" -o json)
  ACCT_NAME=$(echo "$CURRENT" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  ACCT_ID=$(echo "$CURRENT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  ok "Logged in: $ACCT_NAME ($ACCT_ID)"

  [ -n "$ARM_TENANT_ID" ] || err "Could not detect tenant ID. Run: az login"
  export ARM_TENANT_ID
}

# ── Run one layer ─────────────────────────────────────────────
run_layer() {
  local LAYER="$1"
  local ACTION="${2:-plan}"
  local FULL="environments/$LAYER"

  [ -d "$FULL" ] || err "Layer not found: $FULL"

  # Set subscription based on layer
  case "$LAYER" in
    prod/05-workload) export ARM_SUBSCRIPTION_ID="$PROD_SUB"   ;;
    dev/05-workload)  export ARM_SUBSCRIPTION_ID="$NONPROD_SUB" ;;
    *)                export ARM_SUBSCRIPTION_ID="$PLATFORM_SUB" ;;
  esac

  sep
  log "Layer: ${BOLD}$LAYER${NC}  Action: ${BOLD}$ACTION${NC}  Sub: $ARM_SUBSCRIPTION_ID"

  pushd "$FULL" > /dev/null

  # Build -var-file args — always pass terraform.tfvars, add local.tfvars if present
  VARFILES=()
  if [ -f "terraform.tfvars" ]; then
    VARFILES+=("-var-file=terraform.tfvars")
    ok "Using terraform.tfvars"
  else
    warn "No terraform.tfvars found in $FULL"
  fi
  if [ -f "local.tfvars" ]; then
    VARFILES+=("-var-file=local.tfvars")
    ok "Using local.tfvars (secrets)"
  fi

  # Check for required local.tfvars
  case "$LAYER" in
    shared/04-hub|dev/05-workload|prod/05-workload)
      if [ ! -f "local.tfvars" ]; then
        warn "local.tfvars missing in $FULL"
        warn "Copy from local.tfvars.example and fill in values:"
        warn "  cp $FULL/local.tfvars.example $FULL/local.tfvars"
        popd > /dev/null
        return 1
      fi
      ;;
  esac

  # Init
  log "terraform init..."
  terraform init -reconfigure -input=false -no-color \
    -backend-config="subscription_id=$PLATFORM_SUB" \
    -backend-config="tenant_id=$ARM_TENANT_ID" \
    > /tmp/tf-init.log 2>&1 \
    && ok "init complete" \
    || { cat /tmp/tf-init.log; err "init failed for $LAYER"; }

  # Validate
  terraform validate -no-color > /dev/null && ok "validate passed" || err "validate failed"

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
        1) err "Plan failed for $LAYER" ;;
      esac
      ;;

    apply)
      if [ ! -f "local.tfplan" ]; then
        warn "No local.tfplan — running plan first..."
        terraform plan "${VARFILES[@]}" -out=local.tfplan -no-color
      fi
      echo ""
      read -rp "  Apply ${BOLD}$LAYER${NC}? [y/N] " CONFIRM
      if [[ "$CONFIRM" =~ ^[yY]$ ]]; then
        terraform apply local.tfplan -no-color
        ok "Apply complete: $LAYER"
        rm -f local.tfplan
      else
        warn "Aborted"
      fi
      ;;

    destroy)
      echo ""
      warn "This will DESTROY all resources in $LAYER"
      read -rp "  Type the layer name to confirm [${LAYER}]: " CONFIRM
      if [ "$CONFIRM" = "$LAYER" ]; then
        terraform destroy "${VARFILES[@]}" -auto-approve -no-color
        ok "Destroy complete: $LAYER"
      else
        warn "Aborted — confirmation did not match"
      fi
      ;;

    *)
      err "Unknown action: $ACTION. Use plan | apply | destroy"
      ;;
  esac

  popd > /dev/null
}

# ── Run all layers in pipeline order ─────────────────────────
run_all() {
  local ACTION="${1:-plan}"
  log "Running all layers — action: ${BOLD}$ACTION${NC}"
  log "Order: shared/03 → shared/04 → dev/01 → dev/02 → dev/05 → shared/05-avnm → prod/01 → prod/02 → prod/05 → shared/05-avnm (again)"
  echo ""

  local LAYERS=(
    "shared/03-management"
    "shared/04-hub"
    "dev/01-management-groups"
    "dev/02-policy"
    "dev/05-workload"
    "shared/05-avnm"
    "prod/01-management-groups"
    "prod/02-policy"
    "prod/05-workload"
    "shared/05-avnm"
  )

  local FAILED=()
  for LAYER in "${LAYERS[@]}"; do
    run_layer "$LAYER" "$ACTION" || FAILED+=("$LAYER")
    echo ""
  done

  sep
  if [ ${#FAILED[@]} -eq 0 ]; then
    ok "All layers completed successfully"
  else
    warn "The following layers had issues:"
    for F in "${FAILED[@]}"; do echo "  ✗ $F"; done
    exit 1
  fi
}

# ── Main ──────────────────────────────────────────────────────
check_prereqs
echo ""

case "${1:-}" in
  "")       run_all plan ;;
  "all")    run_all "${2:-plan}" ;;
  *)        run_layer "$1" "${2:-plan}" ;;
esac
