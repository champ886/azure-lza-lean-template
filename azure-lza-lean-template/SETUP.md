# Setup Guide — Azure LZA Lean Template

This is a template repository. Before deploying, replace all placeholder values with your own.

## Placeholder Reference

| Placeholder | Description | Example |
|---|---|---|
| `YOUR_TENANT_ID` | Entra ID tenant ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `YOUR_PLATFORM_SUBSCRIPTION_ID` | Platform subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `YOUR_NONPROD_SUBSCRIPTION_ID` | Non-production workload subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `YOUR_PROD_SUBSCRIPTION_ID` | Production workload subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `YOUR_ORG_PREFIX` | Short org prefix for resource naming (2-4 chars) | `cc` |
| `YOUR_ORG_NAME` | Full organisation name | `Cloud Compass` |
| `YOUR_SECURITY_EMAIL` | Email for Defender alerts and budget notifications | `platform@yourorg.com` |
| `YOUR_TFSTATE_SA_NAME` | Globally unique storage account name for tfstate | `myorgtfstate001` |
| `YOUR_GITHUB_ORG` | GitHub username or org | `myorg` |
| `YOUR_GITHUB_REPO` | GitHub repository name | `azure-lza-lean` |

## Quick Substitution

Run this from the repo root to replace all placeholders at once:

```bash
# Set your values
TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
PLATFORM_SUB="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
NONPROD_SUB="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
PROD_SUB="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
ORG_PREFIX="cc"
ORG_NAME="Cloud Compass"
SECURITY_EMAIL="platform@yourorg.com"
TFSTATE_SA_NAME="myorgtfstate001"
GITHUB_ORG="myorg"
GITHUB_REPO="azure-lza-lean"

# Replace all placeholders
find . -type f \( -name "*.tf" -o -name "*.tfvars" -o -name "*.sh" -o -name "*.yml" -o -name "*.md" \) \
  -not -path "./.git/*" \
  -exec sed -i \
    -e "s/YOUR_TENANT_ID/$TENANT_ID/g" \
    -e "s/YOUR_PLATFORM_SUBSCRIPTION_ID/$PLATFORM_SUB/g" \
    -e "s/YOUR_NONPROD_SUBSCRIPTION_ID/$NONPROD_SUB/g" \
    -e "s/YOUR_PROD_SUBSCRIPTION_ID/$PROD_SUB/g" \
    -e "s/YOUR_ORG_PREFIX/$ORG_PREFIX/g" \
    -e "s/YOUR_ORG_NAME/$ORG_NAME/g" \
    -e "s/YOUR_SECURITY_EMAIL/$SECURITY_EMAIL/g" \
    -e "s/YOUR_TFSTATE_SA_NAME/$TFSTATE_SA_NAME/g" \
    -e "s/YOUR_GITHUB_ORG/$GITHUB_ORG/g" \
    -e "s/YOUR_GITHUB_REPO/$GITHUB_REPO/g" \
  {} \;

echo "All placeholders replaced"
```

## Next Steps

After substitution follow the full deployment guide in [RUNBOOK.md](RUNBOOK.md).

```bash
# 1. Run bootstrap
./bootstrap.sh

# 2. Deploy via GitHub Actions
# Actions → ALZ Deploy → Run workflow → plan-and-apply

# 3. Or deploy locally
azure-lza
./local-test.sh
```
