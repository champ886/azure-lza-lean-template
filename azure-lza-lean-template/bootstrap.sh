#!/bin/bash
# =============================================================
# bootstrap.sh
# One-time setup script for Azure LZA Lean
# Run once from local CLI before first terraform deploy
#
# What this script does:
#   1. Registers required Azure resource providers
#   2. Creates tfstate resource group
#   3. Creates tfstate storage account + container (via az rest)
#   4. Creates OIDC App Registration + Service Principal
#   5. Creates federated credentials for GitHub Actions
#   6. Assigns Owner role on all 3 subscriptions
#   7. Assigns Management Group Contributor at tenant root
#   8. Registers all resource providers on all 3 subs
#   9. Sets GitHub Secrets, Variables, and Environments via gh CLI
#  10. Prints summary of everything created
# =============================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
PLATFORM_SUB="YOUR_PLATFORM_SUBSCRIPTION_ID"
PROD_SUB="YOUR_PROD_SUBSCRIPTION_ID"
NONPROD_SUB="YOUR_NONPROD_SUBSCRIPTION_ID"
LOCATION="australiaeast"
SA_NAME="YOUR_TFSTATE_SA_NAME"
RG_NAME="YOUR_ORG_PREFIX-tfstate-platform"
GITHUB_ORG="YOUR_GITHUB_ORG"
GITHUB_REPO="YOUR_GITHUB_REPO"
SSH_KEY_PATH="$HOME/.ssh/azure-lza-router.pub"
ARM="https://management.azure.com"
API="2023-01-01"
SA_BASE="$ARM/subscriptions/$PLATFORM_SUB/resourceGroups/$RG_NAME/providers/Microsoft.Storage/storageAccounts/$SA_NAME"

# ── Colours ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

# =============================================================
# STEP 1 — Detect tenant and validate login
# Gets tenant ID from current az login session
# =============================================================
log "Detecting tenant and login context..."
TENANT=$(az account show --query tenantId -o tsv)
CURRENT_USER=$(az account show --query "user.name" -o tsv)
ok "Logged in as: $CURRENT_USER"
ok "Tenant:       $TENANT"
ok "Platform sub: $PLATFORM_SUB"

# =============================================================
# STEP 2 — Register Microsoft.Storage on platform sub first
# Required before storage account can be created
# =============================================================
log "Step 2: Registering Microsoft.Storage on platform sub..."
az provider register \
  --namespace Microsoft.Storage \
  --subscription "$PLATFORM_SUB" \
  --wait \
  --output none
ok "Microsoft.Storage registered"

# =============================================================
# STEP 3 — Create tfstate resource group
# Idempotent — safe to re-run if already exists
# =============================================================
log "Step 3: Creating tfstate resource group..."
az group create \
  --name "$RG_NAME" \
  --location "$LOCATION" \
  --subscription "$PLATFORM_SUB" \
  --output none
ok "$RG_NAME created"

# =============================================================
# STEP 4 — Create storage account via az rest
# Uses az rest instead of az storage to bypass subscription
# resolution bug in the az storage CLI module
# Idempotent — skips creation if account already exists
# =============================================================
log "Step 4: Creating tfstate storage account..."
EXISTING_SA=$(az rest \
  --method GET \
  --url "$SA_BASE?api-version=$API" \
  --query properties.provisioningState \
  -o tsv 2>/dev/null || echo "")

if [ "$EXISTING_SA" = "Succeeded" ]; then
  warn "$SA_NAME already exists — skipping creation"
else
  az rest \
    --method PUT \
    --url "$SA_BASE?api-version=$API" \
    --body "{
      \"sku\": {\"name\": \"Standard_LRS\"},
      \"kind\": \"StorageV2\",
      \"location\": \"$LOCATION\",
      \"properties\": {
        \"minimumTlsVersion\": \"TLS1_2\",
        \"allowBlobPublicAccess\": false,
        \"supportsHttpsTrafficOnly\": true,
        \"accessTier\": \"Hot\"
      }
    }" \
    --output none
  ok "$SA_NAME created — polling for Succeeded state..."

  # Poll until storage account is fully provisioned
  for i in $(seq 1 24); do
    STATE=$(az rest \
      --method GET \
      --url "$SA_BASE?api-version=$API" \
      --query properties.provisioningState \
      -o tsv 2>/dev/null)
    ok "[$i/24] $STATE"
    [ "$STATE" = "Succeeded" ] && break
    [ "$i" -eq 24 ] && { echo "ERROR: timed out"; exit 1; }
    sleep 5
  done
fi

# =============================================================
# STEP 5 — Create tfstate blob container
# Idempotent — safe to re-run if already exists
# =============================================================
log "Step 5: Creating tfstate container..."
az rest \
  --method PUT \
  --url "$SA_BASE/blobServices/default/containers/tfstate?api-version=$API" \
  --body '{"properties": {"publicAccess": "None"}}' \
  --output none
ok "tfstate container ready"

# Enable soft delete — protects state files from accidental deletion
az rest \
  --method PUT \
  --url "$SA_BASE/blobServices/default?api-version=$API" \
  --body '{"properties": {"deleteRetentionPolicy": {"enabled": true, "days": 7}}}' \
  --output none
ok "Soft delete enabled (7 days)"

# =============================================================
# STEP 6 — Create OIDC App Registration + Service Principal
# Used by GitHub Actions to authenticate to Azure without
# storing any credentials — federated identity only
# Idempotent — reuses existing app if already created
# =============================================================
log "Step 6: Creating OIDC App Registration..."
EXISTING_APP=$(az ad app list \
  --display-name "sp-github-${GITHUB_REPO}" \
  --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP" ]; then
  APP_ID="$EXISTING_APP"
  warn "App registration already exists: $APP_ID"
else
  APP_ID=$(az ad app create \
    --display-name "sp-github-${GITHUB_REPO}" \
    --query appId -o tsv)
  ok "App registration created: $APP_ID"
fi

# Create service principal if it doesn't exist
EXISTING_SP=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || echo "")
if [ -n "$EXISTING_SP" ]; then
  SP_OBJ="$EXISTING_SP"
  warn "Service principal already exists: $SP_OBJ"
else
  az ad sp create --id "$APP_ID" --output none
  SP_OBJ=$(az ad sp show --id "$APP_ID" --query id -o tsv)
  ok "Service principal created: $SP_OBJ"
fi

# =============================================================
# STEP 7 — Create federated credentials
# Allows GitHub Actions on main branch and PRs to authenticate
# using OIDC tokens — no client secrets stored anywhere
# Idempotent — skips if credential already exists
# Points at: YOUR_GITHUB_ORG/YOUR_GITHUB_REPO
# =============================================================
log "Step 7: Creating federated credentials..."

# Delete and recreate if repo org changed (cloud-compass -> YOUR_GITHUB_ORG)
for CRED_NAME in "github-main" "github-pr"; do
  EXISTING_CRED=$(az ad app federated-credential list \
    --id "$APP_ID" \
    --query "[?name=='$CRED_NAME'].id" -o tsv 2>/dev/null || echo "")

  if [ -n "$EXISTING_CRED" ]; then
    # Check if it points at the right repo
    EXISTING_SUBJECT=$(az ad app federated-credential list \
      --id "$APP_ID" \
      --query "[?name=='$CRED_NAME'].subject" -o tsv 2>/dev/null)
    if [[ "$EXISTING_SUBJECT" == *"$GITHUB_ORG/$GITHUB_REPO"* ]]; then
      warn "$CRED_NAME already correct — skipping"
      continue
    else
      warn "$CRED_NAME points at wrong repo ($EXISTING_SUBJECT) — recreating"
      az ad app federated-credential delete \
        --id "$APP_ID" \
        --federated-credential-id "$EXISTING_CRED" \
        --output none
    fi
  fi

  if [ "$CRED_NAME" = "github-main" ]; then
    SUBJECT="repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"
  else
    SUBJECT="repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"
  fi

  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\":\"$CRED_NAME\",
    \"issuer\":\"https://token.actions.githubusercontent.com\",
    \"subject\":\"$SUBJECT\",
    \"audiences\":[\"api://AzureADTokenExchange\"]
  }" --output none
  ok "$CRED_NAME created → $SUBJECT"
done

# =============================================================
# STEP 8 — Assign Owner role on all 3 subscriptions
# Service principal needs Owner to create all LZA resources
# Also assigns Management Group Contributor at tenant root
# so it can create and manage the MG hierarchy
# Idempotent — skips if assignment already exists
# =============================================================
log "Step 8: Assigning roles..."

for SUB in "$PLATFORM_SUB" "$PROD_SUB" "$NONPROD_SUB"; do
  EXISTING=$(az role assignment list \
    --assignee "$SP_OBJ" \
    --role Owner \
    --scope "/subscriptions/$SUB" \
    --query "[0].id" -o tsv 2>/dev/null || echo "")
  if [ -n "$EXISTING" ]; then
    warn "Owner already assigned on $SUB — skipping"
  else
    az role assignment create \
      --role Owner \
      --assignee-object-id "$SP_OBJ" \
      --assignee-principal-type ServicePrincipal \
      --scope "/subscriptions/$SUB" \
      --output none
    ok "Owner assigned on $SUB"
  fi
done

EXISTING_MG=$(az role assignment list \
  --assignee "$SP_OBJ" \
  --role "Management Group Contributor" \
  --scope "/providers/Microsoft.Management/managementGroups/$TENANT" \
  --query "[0].id" -o tsv 2>/dev/null || echo "")
if [ -n "$EXISTING_MG" ]; then
  warn "Management Group Contributor already assigned — skipping"
else
  az role assignment create \
    --role "Management Group Contributor" \
    --assignee-object-id "$SP_OBJ" \
    --assignee-principal-type ServicePrincipal \
    --scope "/providers/Microsoft.Management/managementGroups/$TENANT" \
    --output none
  ok "Management Group Contributor assigned at tenant root"
fi

# =============================================================
# STEP 9 — Register resource providers on all 3 subscriptions
# Terraform will fail if providers are not registered before
# it tries to create resources in those namespaces
# Skips Microsoft.NetworkManager — not available in australiaeast
# =============================================================
log "Step 9: Registering resource providers on all subscriptions..."
PROVIDERS=(
  Microsoft.Network
  Microsoft.Compute
  Microsoft.KeyVault
  Microsoft.Storage
  Microsoft.ContainerRegistry
  Microsoft.OperationalInsights
  Microsoft.Security
  Microsoft.PolicyInsights
)

for SUB in "$PLATFORM_SUB" "$PROD_SUB" "$NONPROD_SUB"; do
  ok "Sub: $SUB"
  for RP in "${PROVIDERS[@]}"; do
    az provider register \
      --namespace "$RP" \
      --subscription "$SUB" \
      --wait \
      --output none
    echo "    ✓ $RP"
  done
done

# =============================================================
# STEP 10 — Set GitHub Secrets, Variables, and Environments
# Uses gh CLI to configure the repo without portal access
# Requires: gh auth login completed before running this script
# =============================================================
log "Step 10: Configuring GitHub repo..."

# Check gh CLI is available and authenticated
if ! command -v gh &>/dev/null; then
  warn "gh CLI not found — skipping GitHub setup"
  warn "Install with: sudo apt install gh -y"
else
  GH_USER=$(gh auth status 2>&1 | grep "Logged in" | awk '{print $NF}' || echo "")
  if [ -z "$GH_USER" ]; then
    warn "gh CLI not authenticated — run: gh auth login"
    warn "Skipping GitHub setup — add secrets manually"
  else
    ok "gh CLI authenticated"

    # Get storage account resource ID for flow logs variable
    SA_ID=$(az rest \
      --method GET \
      --url "$SA_BASE?api-version=$API" \
      --query id -o tsv)

    # Secrets — sensitive values, encrypted in GitHub
    gh secret set AZURE_CLIENT_ID \
      --body "$APP_ID" \
      --repo "$GITHUB_ORG/$GITHUB_REPO"
    ok "Secret: AZURE_CLIENT_ID"

    gh secret set AZURE_TENANT_ID \
      --body "$TENANT" \
      --repo "$GITHUB_ORG/$GITHUB_REPO"
    ok "Secret: AZURE_TENANT_ID"

    gh secret set AZURE_SUBSCRIPTION_ID \
      --body "$PLATFORM_SUB" \
      --repo "$GITHUB_ORG/$GITHUB_REPO"
    ok "Secret: AZURE_SUBSCRIPTION_ID"

    # SSH public key for router VM — reads from file
    if [ -f "$SSH_KEY_PATH" ]; then
      gh secret set ROUTER_SSH_PUBLIC_KEY \
        < "$SSH_KEY_PATH" \
        --repo "$GITHUB_ORG/$GITHUB_REPO"
      ok "Secret: ROUTER_SSH_PUBLIC_KEY (from $SSH_KEY_PATH)"
    else
      warn "SSH key not found at $SSH_KEY_PATH"
      warn "Generate with: ssh-keygen -t ed25519 -f ~/.ssh/azure-lza-router"
      warn "Then set manually: gh secret set ROUTER_SSH_PUBLIC_KEY < ~/.ssh/azure-lza-router.pub --repo $GITHUB_ORG/$GITHUB_REPO"
    fi

    # Variable — non-sensitive, visible in logs
    # Uses gh api because gh variable requires gh >= 2.32.0
    gh api \
      --method POST \
      "repos/$GITHUB_ORG/$GITHUB_REPO/actions/variables" \
      -f name="FLOW_LOG_STORAGE_ACCOUNT_ID" \
      -f value="$SA_ID" \
      2>/dev/null || \
    gh api \
      --method PATCH \
      "repos/$GITHUB_ORG/$GITHUB_REPO/actions/variables/FLOW_LOG_STORAGE_ACCOUNT_ID" \
      -f name="FLOW_LOG_STORAGE_ACCOUNT_ID" \
      -f value="$SA_ID"
    ok "Variable: FLOW_LOG_STORAGE_ACCOUNT_ID"

    # Environments — dev has no gate, prod requires approval
    gh api --method PUT \
      "repos/$GITHUB_ORG/$GITHUB_REPO/environments/dev" \
      --input /dev/null > /dev/null
    ok "Environment: dev (no gate)"

    gh api --method PUT \
      "repos/$GITHUB_ORG/$GITHUB_REPO/environments/prod" \
      --input /dev/null > /dev/null
    ok "Environment: prod (add required reviewers in portal)"

    echo ""
    log "Verifying GitHub configuration..."
    echo "  Secrets:"
    gh secret list --repo "$GITHUB_ORG/$GITHUB_REPO" | awk '{print "    "$0}'
    echo "  Variables:"
    gh api "repos/$GITHUB_ORG/$GITHUB_REPO/actions/variables" \
      --jq '.variables[] | "    " + .name + " = " + .value'
    echo "  Environments:"
    gh api "repos/$GITHUB_ORG/$GITHUB_REPO/environments" \
      --jq '.environments[].name | "    " + .'
  fi
fi

# =============================================================
# DONE — Print summary
# =============================================================
SA_ID=$(az rest \
  --method GET \
  --url "$SA_BASE?api-version=$API" \
  --query id -o tsv 2>/dev/null || echo "unknown")

echo ""
echo "============================================"
echo " Bootstrap complete"
echo "============================================"
echo ""
echo "Azure resources created:"
echo "  Resource group:    $RG_NAME"
echo "  Storage account:   $SA_NAME"
echo "  Container:         tfstate"
echo "  App registration:  sp-github-$GITHUB_REPO ($APP_ID)"
echo "  Service principal: $SP_OBJ"
echo ""
echo "GitHub repo configured: $GITHUB_ORG/$GITHUB_REPO"
echo ""
echo "Next steps:"
echo "  1. Add required reviewer to prod environment:"
echo "     https://github.com/$GITHUB_ORG/$GITHUB_REPO/settings/environments"
echo "  2. Generate SSH key if not done:"
echo "     ssh-keygen -t ed25519 -f ~/.ssh/azure-lza-router"
echo "  3. Copy local.tfvars.example files and fill in values"
echo "  4. Run: ./local-test.sh shared/03-management"
