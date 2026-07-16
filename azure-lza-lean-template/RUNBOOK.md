# Azure LZA Lean — Runbook

Complete operational guide for deploying, managing, and troubleshooting the Azure LZA Lean landing zone.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Azure CLI | `>= 2.60` — `az version` |
| Terraform | `>= 1.7` — `terraform version` |
| GitHub CLI | `>= 2.32` — `gh version` |
| 3 Azure subscriptions | sub-platform-prod, sub-workload-nonprod, sub-workload-prod |
| GitHub repo | `YOUR_GITHUB_ORG/YOUR_GITHUB_REPO` |

---

## Initial Setup

### Step 1 — Clone repo

```bash
git clone https://github.com/YOUR_GITHUB_ORG/YOUR_GITHUB_REPO.git
cd azure-lza-lean
```

### Step 2 — Generate SSH key for router VM

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure-lza-router -C "azure-lza-router"
cat ~/.ssh/azure-lza-router.pub   # copy this value
```

### Step 3 — Create local.auto.tfvars files

These files are gitignored and contain secrets for local testing only.

```bash
# Hub layer — SSH public key
cp environments/shared/04-hub/local.auto.tfvars.example \
   environments/shared/04-hub/local.auto.tfvars
# Edit and paste your RSA public key

# Dev workload — storage account resource ID
cp environments/dev/05-workload/local.auto.tfvars.example \
   environments/dev/05-workload/local.auto.tfvars

# Prod workload
cp environments/prod/05-workload/local.auto.tfvars.example \
   environments/prod/05-workload/local.auto.tfvars

# Get storage account resource ID
az storage account show \
  --name YOUR_TFSTATE_SA_NAME \
  --resource-group YOUR_ORG_PREFIX-tfstate-platform \
  --subscription "YOUR_PLATFORM_SUBSCRIPTION_ID" \
  --query id -o tsv
# Paste output into both workload local.auto.tfvars files
```

### Step 4 — Add auth helpers to ~/.bashrc

```bash
cat >> ~/.bashrc << 'EOF'
# Azure LZA auth helpers
azure-lza() {
  export ARM_USE_OIDC=false
  export ARM_USE_AZURE_CLI_AUTH=true
  export ARM_TENANT_ID="YOUR_TENANT_ID"
  export ARM_SUBSCRIPTION_ID="YOUR_PLATFORM_SUBSCRIPTION_ID"
  echo "✅ Azure LZA auth set (platform sub)"
}
azure-lza-dev() {
  azure-lza
  export ARM_SUBSCRIPTION_ID="YOUR_NONPROD_SUBSCRIPTION_ID"
  echo "✅ Azure LZA auth set (nonprod sub)"
}
azure-lza-prod() {
  azure-lza
  export ARM_SUBSCRIPTION_ID="YOUR_PROD_SUBSCRIPTION_ID"
  echo "✅ Azure LZA auth set (prod sub)"
}
azure-unset() {
  unset ARM_USE_OIDC ARM_USE_AZURE_CLI_AUTH ARM_TENANT_ID ARM_SUBSCRIPTION_ID
  echo "✅ Azure ARM env vars cleared"
}
EOF
source ~/.bashrc
```

### Step 5 — Run bootstrap (once only)

```bash
az login
./bootstrap.sh
```

Bootstrap creates:
- tfstate storage account `YOUR_TFSTATE_SA_NAME` in `YOUR_ORG_PREFIX-tfstate-platform`
- OIDC App Registration `sp-github-azure-lza-lean`
- Owner role on all 3 subscriptions
- Management Group Contributor at tenant root
- GitHub Secrets, Variables, and Environments

### Step 6 — Add ROUTER_SSH_PUBLIC_KEY to GitHub Secrets

```bash
gh secret set ROUTER_SSH_PUBLIC_KEY \
  < ~/.ssh/azure-lza-router.pub \
  --repo YOUR_GITHUB_ORG/YOUR_GITHUB_REPO
```

---

## Deploy Order

### Via GitHub Actions (recommended)

```
Actions → ALZ Deploy → Run workflow → plan-and-apply → Run
```

Pipeline runs in this order:

```
shared/03-management    LAW, DNS zones, Defender, budgets
shared/04-hub           Hub VNet, NAT GW, router VM
dev/01-management-groups  MG hierarchy
dev/02-policy           Azure Policy (audit mode)
dev/05-workload         Dev spoke, Key Vault, private endpoints
shared/05-avnm          AVNM peerings + security admin rules
```

Prod layers are commented out in `alz-deploy.yml` until prod workload is ready.

### Via local-test.sh

```bash
azure-lza   # set auth env vars
./local-test.sh shared/03-management apply
./local-test.sh shared/04-hub apply
./local-test.sh dev/01-management-groups apply
./local-test.sh dev/02-policy apply
./local-test.sh dev/05-workload apply
./local-test.sh shared/05-avnm apply
```

### Via terraform directly

```bash
azure-lza
cd environments/shared/03-management
terraform init
terraform apply -var-file=terraform.tfvars
```

---

## Destroy Order

### Via GitHub Actions

```
Actions → ALZ Destroy → Run workflow → type: DESTROY → Run
```

Reverse order: AVNM → dev workload → dev policy → dev MGs → hub → management

### Via local

```bash
./local-test.sh shared/05-avnm destroy
./local-test.sh dev/05-workload destroy
./local-test.sh dev/02-policy destroy
./local-test.sh dev/01-management-groups destroy
./local-test.sh shared/04-hub destroy
./local-test.sh shared/03-management destroy
```

---

## Verification

### Management layer

```bash
# LAW workspace
az monitor log-analytics workspace show \
  --resource-group rg-management-cc \
  --workspace-name law-cc-platform \
  --query "{name:name, retentionDays:retentionInDays}" -o table

# Private DNS zones (expect 8)
az network private-dns zone list \
  --resource-group rg-management-cc \
  --query "[].{Name:name}" -o table
```

### Hub layer

```bash
# Hub VNet
az network vnet show \
  --name vnet-hub-cc \
  --resource-group rg-hub-cc \
  --query "{name:name, addressSpace:addressSpace.addressPrefixes}" -o table

# Router VM — confirm IP forwarding is ON
az network nic show \
  --name nic-router-cc \
  --resource-group rg-hub-cc \
  --query "{ipForwarding:enableIpForwarding, ip:ipConfigurations[0].privateIPAddress}" -o table

# NAT Gateway
az network nat gateway show \
  --name natgw-hub-cc \
  --resource-group rg-hub-cc \
  --query "{name:name, state:provisioningState}" -o table
```

### AVNM

```bash
# Network groups
az network manager group list \
  --network-manager-name avnm-cc \
  --resource-group rg-hub-cc \
  --query "[].{Name:name}" -o table

# Peering on dev spoke — should show AVNM-managed peering
az network vnet peering list \
  --vnet-name vnet-spoke-dev-cc \
  --resource-group rg-workload-dev-cc \
  --subscription "YOUR_NONPROD_SUBSCRIPTION_ID" \
  --query "[].{Name:name, State:peeringState}" -o table

# Security admin deployments
az network manager list-deployment-status \
  --name avnm-cc \
  --resource-group rg-hub-cc \
  --regions australiaeast \
  --query "value[].{Type:deploymentType, Status:deploymentStatus}" -o table
```

### Dev workload

```bash
# Key Vault — confirm no public access
az keyvault show \
  --name kv-dev-cc \
  --resource-group rg-workload-dev-cc \
  --subscription "YOUR_NONPROD_SUBSCRIPTION_ID" \
  --query "{name:name, publicAccess:properties.publicNetworkAccess}" -o table

# Private endpoint
az network private-endpoint list \
  --resource-group rg-workload-dev-cc \
  --subscription "YOUR_NONPROD_SUBSCRIPTION_ID" \
  --query "[].{Name:name, State:provisioningState}" -o table
```

### End-to-end network test

```bash
# Deploy test VM
cd environments/dev/test
terraform init
terraform apply

# Wait 2 minutes for cloud-init, then run validation
$(terraform output -raw validation_command)

# Expected output:
# ROUTING: default via 10.2.1.4         ← traffic via router VM
# DNS: kv-dev-cc → 10.10.10.x           ← private IP resolution
# EGRESS: <NAT GW public IP>             ← shared egress
# HUB: 3 packets received                ← hub reachable

# Destroy test VM when done
terraform destroy
```

---

## Troubleshooting

### State file has no outputs

Happens when outputs were added to `main.tf` after initial apply.

```bash
cd environments/shared/03-management
terraform apply -refresh-only -var-file=terraform.tfvars
terraform output   # verify outputs are now populated
```

Run `refresh-only` on each affected layer.

### State lock — stale lock from interrupted run

```bash
terraform force-unlock <lock-id-from-error-message>
```

### VM SKU not available

B-series frequently out of capacity in australiaeast.

```bash
# Find available sizes
az vm list-skus \
  --location australiaeast \
  --resource-type virtualMachines \
  --output table | grep -v NotAvailable
```

Update `router_vm_size` in `environments/shared/04-hub/terraform.tfvars`.

### SubscriptionNotFound on az storage commands

Known az CLI bug with storage module subscription resolution. Use `az rest` instead:

```bash
az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<sa>?api-version=2023-01-01"
```

### AVNM routing not supported in azurerm provider

AVNM routing configuration (`azurerm_network_manager_routing_configuration`) is not yet implemented in the azurerm Terraform provider. Route tables in the workload module handle UDRs as interim solution. Track: https://github.com/hashicorp/terraform-provider-azurerm/issues/27180

### GHA pipeline — artifact not found on apply

Artifacts expire after 1 day. Use `plan-and-apply` action instead of separate `plan` then `apply` runs.

```
Actions → ALZ Deploy → Run workflow → plan-and-apply
```

### Policy assignment — effect not allowed

Some built-in Azure policies have restricted allowed effects. Check:

```bash
az policy definition show \
  --name <policy-definition-id> \
  --query "properties.parameters.effect.allowedValues" -o tsv
```

Use the allowed value instead of `Deny` if the policy doesn't support it.

---

## Phase 2 Graduation — OPNsense

When ready to replace the router VM with OPNsense active-active:

1. Deploy OPNsense pair + Internal Load Balancer into hub `NVASubnet`
2. Note the ILB frontend private IP (e.g. `10.2.1.5`)
3. Update `environments/shared/05-avnm/terraform.tfvars`:
   ```hcl
   nva_next_hop_ip_override = "10.2.1.5"
   ```
4. Run `./local-test.sh shared/05-avnm apply`
5. AVNM updates the routing config — all spoke route tables updated automatically
6. Zero changes to any spoke Terraform
7. Remove router VM resources from `modules/hub/main.tf`

---

## Resource Groups Summary

| Resource Group | Subscription | Contents |
|---|---|---|
| `YOUR_ORG_PREFIX-tfstate-platform` | platform | tfstate storage account |
| `rg-management-cc` | platform | LAW, AMPLS, 8 DNS zones, Defender |
| `rg-hub-cc` | platform | Hub VNet, NAT GW, router VM, AVNM, NSGs |
| `rg-workload-dev-cc` | nonprod | Dev spoke VNet, subnets, NSGs, Key Vault, PEs |
| `rg-workload-prod-cc` | prod | Prod spoke VNet, subnets, NSGs, Key Vault, PEs |
| `NetworkWatcherRG` | nonprod/prod | Auto-created by Azure — Network Watcher |

---

## Cost Summary

| Component | Phase 1 | Phase 2 |
|---|---|---|
| Router VM (B-series) | ~$8/mo | removed |
| NAT Gateway | ~$32/mo | ~$32/mo |
| NAT GW public IP | ~$4/mo | ~$4/mo |
| AVNM (2 peerings) | ~$22/mo | ~$22/mo |
| OPNsense pair + ILB | — | ~$60/mo |
| Private endpoints | ~$7/mo each | ~$7/mo each |
| LAW (PerGB2018) | usage-based | usage-based |
| **Total** | **~$66/mo** | **~$118/mo** |

Azure Firewall alternative: ~$950/mo
