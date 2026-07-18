#!/bin/bash
# =============================================================
# deploy-local.sh
# Full local deploy or destroy in correct order
# Uses local-test.sh for each layer
#
# Usage:
#   ./deploy-local.sh          # apply all layers (default)
#   ./deploy-local.sh apply    # apply all layers
#   ./deploy-local.sh plan     # plan all layers
#   ./deploy-local.sh destroy  # destroy all in reverse order
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-apply}"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
sep()  { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Prereq check ─────────────────────────────────────────────
az account show > /dev/null 2>&1 || err "Not logged in. Run: az login"
ok "Logged in as: $(az account show --query user.name -o tsv)"
echo ""

# ── Layer order ───────────────────────────────────────────────
DEPLOY_LAYERS=(
  "shared/03-management"
  "shared/04-hub"
  "dev/01-management-groups"
  "dev/02-policy"
  "dev/05-workload"
  "shared/05-avnm"
)

DESTROY_LAYERS=(
  "shared/05-avnm"
  "dev/05-workload"
  "dev/02-policy"
  "dev/01-management-groups"
  "shared/04-hub"
  "shared/03-management"
)

case "$ACTION" in
  destroy) LAYERS=("${DESTROY_LAYERS[@]}") ;;
  *)       LAYERS=("${DEPLOY_LAYERS[@]}") ;;
esac

TOTAL=${#LAYERS[@]}
log "Action: ${BOLD}$ACTION${NC}  Layers: $TOTAL"
sep

# ── Run each layer ────────────────────────────────────────────
for i in "${!LAYERS[@]}"; do
  LAYER="${LAYERS[$i]}"
  NUM=$((i + 1))
  log "[$NUM/$TOTAL] $LAYER"

  "$SCRIPT_DIR/local-test.sh" "$LAYER" "$ACTION" \
    || err "[$NUM/$TOTAL] $LAYER FAILED — stopping"

  ok "[$NUM/$TOTAL] $LAYER done"
  echo ""
done

sep
ok "All $TOTAL layers completed — action: $ACTION"
