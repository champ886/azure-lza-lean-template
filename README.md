# Azure LZA Lean — YOUR_ORG_NAME.au

> **Lean philosophy:** Start with what you need today. Graduate to what you need tomorrow. No Azure Firewall at $950/mo on day one — a $8 router VM does the same job while you validate the architecture.

## What is this?

A production-grade Azure Landing Zone built for tech scale-ups. Hub-and-spoke networking, private endpoints throughout, AVNM-managed peerings, Azure Policy enforcement — all IaC-first with zero manual portal steps.

The "lean" in the name means:

| What you'd normally spend | What this costs | How |
|---|---|---|
| Azure Firewall | ~$950/mo | Router VM B-series ~$8/mo — Phase 1 |
| Multiple NAT Gateways | ~$100+/mo | One shared NAT GW in hub ~$36/mo |
| Manual peering management | Engineering time | AVNM owns all peerings automatically |
| Per-spoke DNS zones | Duplication | 8 shared private DNS zones, linked to all spokes |

**Phase 1: ~$66/mo → Phase 2: ~$118/mo → Azure Firewall if ever needed: ~$950/mo**

---

## Architecture

```
                        ┌─────────────────────────────────┐
                        │         Internet                 │
                        └──────────────┬──────────────────┘
                                       │ egress only
                                       │ via NAT GW
                     ┌─────────────────▼─────────────────────────────┐
                     │         Hub VNet — 10.2.0.0/16                │
                     │         sub-platform-prod                      │
                     │                                                │
                     │  ┌──────────────┐   ┌────────────────────┐   │
                     │  │  Router VM   │   │    NAT Gateway     │   │
                     │  │  10.2.1.4    │──▶│    + public IP     │   │
                     │  │  B-series    │   │    ~$36/mo         │   │
                     │  │  IP fwd ON   │   │                    │   │
                     │  └──────────────┘   └────────────────────┘   │
                     │                                                │
                     │  Phase 2: OPNsense active-active + ILB        │
                     │  replaces router VM — one variable change      │
                     │  AVNM propagates to all spokes automatically   │
                     └──────────┬─────────────────┬──────────────────┘
                                │ AVNM peering     │ AVNM peering
                    ┌───────────▼───────┐ ┌────────▼──────────┐
                    │   Dev Spoke       │ │   Prod Spoke      │
                    │   10.10.0.0/16    │ │   10.20.0.0/16    │
                    │   sub-nonprod     │ │   sub-prod        │
                    │                   │ │                   │
                    │  WorkloadSubnet   │ │  WorkloadSubnet   │
                    │  AKSSubnet        │ │  AKSSubnet        │
                    │  PESubnet         │ │  PESubnet         │
                    │                   │ │                   │
                    │  PE: Key Vault    │ │  PE: Key Vault    │
                    │  PE: ACR          │ │  PE: ACR          │
                    │  NSG per subnet   │ │  NSG per subnet   │
                    │  Route → 10.2.1.4 │ │  Route → 10.2.1.4│
                    └───────────────────┘ └───────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  Azure Virtual Network Manager                                  │
  │  Owns all peerings · Security admin rules · (routing: roadmap)  │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  Shared Management — sub-platform-prod                          │
  │  LAW · AMPLS · 8 Private DNS Zones · Defender · Budgets        │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  Management Group Hierarchy                                     │
  │  Tenant Root → Cloud Compass → Platform / Workloads            │
  │                                         ├── Non-Production      │
  │                                         └── Production          │
  └─────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
azure-lza-lean/
├── modules/                        # Reusable Terraform modules
│   ├── management-groups/          # MG hierarchy + sub associations
│   ├── policy/                     # Azure Policy — audit + deny rules
│   ├── management/                 # LAW, AMPLS, DNS zones, Defender
│   ├── hub/                        # Hub VNet, NAT GW, router VM
│   ├── avnm/                       # AVNM peerings + security admin
│   └── workload/                   # Spoke VNet, NSGs, KV, private endpoints
│
├── environments/
│   ├── shared/                     # Deploys first — shared by all envs
│   │   ├── 03-management/          # LAW, DNS zones, Defender, budgets
│   │   ├── 04-hub/                 # Hub VNet + NAT GW + router VM
│   │   └── 05-avnm/               # AVNM — runs after each spoke
│   ├── dev/
│   │   ├── 01-management-groups/   # MG hierarchy (created once)
│   │   ├── 02-policy/              # Audit mode — no blocking
│   │   └── 05-workload/            # Dev spoke + private endpoints
│   └── prod/
│       ├── 01-management-groups/   # Reads from dev MG state
│       ├── 02-policy/              # Enforce mode + deny public IPs
│       └── 05-workload/            # Prod spoke + private endpoints
│
├── .github/workflows/
│   ├── alz-deploy.yml              # Orchestrator: plan-only | apply | plan-and-apply
│   ├── alz-destroy.yml             # Reverse order destroy
│   ├── layer-03-management.yml     # Reusable layer components
│   ├── layer-04-hub.yml
│   ├── layer-05-avnm.yml
│   ├── layer-01-mg.yml
│   ├── layer-02-policy.yml
│   └── layer-05-workload.yml
│
├── bootstrap.sh                    # One-time setup — run before first deploy
├── local-test.sh                   # Local plan/apply/destroy per layer
├── deploy-local.sh                 # Automated full deploy/destroy locally
└── .gitignore
```

---

## Subscriptions

| Subscription | ID | Purpose |
|---|---|---|
| sub-platform-prod | `YOUR_PLATFORM_SUBSCRIPTION_ID` | Hub, AVNM, LAW, DNS zones |
| sub-workload-nonprod | `YOUR_NONPROD_SUBSCRIPTION_ID` | Dev spoke |
| sub-workload-prod | `YOUR_PROD_SUBSCRIPTION_ID` | Prod spoke |

**Tenant:** `YOUR_TENANT_ID` (Algorhythm.au)

---

## CIDR Plan

| Network | CIDR | Subnets |
|---|---|---|
| Hub | `10.2.0.0/16` | NVASubnet /24, GatewaySubnet /27, BastionSubnet /27, ManagementSubnet /24, NATGWSubnet /24 |
| Dev spoke | `10.10.0.0/16` | WorkloadSubnet /24, AKSSubnet /22, PrivateEndpointSubnet /24 |
| Prod spoke | `10.20.0.0/16` | WorkloadSubnet /24, AKSSubnet /22, PrivateEndpointSubnet /24 |

---

## State Files

| Layer | State key | Subscription |
|---|---|---|
| shared/03-management | `alz/shared/03-management/terraform.tfstate` | platform |
| shared/04-hub | `alz/shared/04-hub/terraform.tfstate` | platform |
| shared/05-avnm | `alz/shared/05-avnm/terraform.tfstate` | platform |
| dev/01-management-groups | `alz/dev/01-management-groups/terraform.tfstate` | platform |
| dev/02-policy | `alz/dev/02-policy/terraform.tfstate` | platform |
| dev/05-workload | `alz/dev/05-workload/terraform.tfstate` | nonprod |
| prod/01-management-groups | `alz/prod/01-management-groups/terraform.tfstate` | platform |
| prod/02-policy | `alz/prod/02-policy/terraform.tfstate` | platform |
| prod/05-workload | `alz/prod/05-workload/terraform.tfstate` | prod |

**Backend:** Storage account `YOUR_TFSTATE_SA_NAME` in `rg-tfstate-platform`

---

## Graduation Path

```
Phase 1 (~$66/mo)    Router VM as UDR next hop
                     NAT GW shared egress
                     AVNM peerings + security admin
                     Private endpoints throughout
                          │
                          │ Change nva_next_hop_ip in 05-avnm tfvars
                          │ AVNM propagates to all spokes — zero spoke changes
                          ▼
Phase 2 (~$118/mo)   OPNsense active-active + ILB
                     Full firewall policy
                     IDS/IPS
                          │
                          │ Only if compliance requires it
                          ▼
Phase 3 (~$950/mo)   Azure Firewall
                     (same AVNM next hop update — zero spoke changes)
```

---

## Quick Start

See [RUNBOOK.md](RUNBOOK.md) for full step-by-step instructions.

```bash
# 1. Bootstrap (once only)
./bootstrap.sh

# 2. Update placeholder values in local-test.sh
#    PLATFORM_SUB, NONPROD_SUB, PROD_SUB, TENANT_ID

# 3a. Deploy locally — automated (recommended)
./deploy-local.sh apply

# 3b. Deploy via GitHub Actions
# Actions → ALZ Deploy → Run workflow → plan-and-apply

# 3c. Deploy locally — layer by layer
./local-test.sh shared/03-management apply
./local-test.sh shared/04-hub apply
./local-test.sh dev/01-management-groups apply
./local-test.sh dev/02-policy apply
./local-test.sh dev/05-workload apply
./local-test.sh shared/05-avnm apply

# 4. Verify
az group list --query "[?starts_with(name,'rg-')].name" -o tsv

# 5. Destroy when needed
./deploy-local.sh destroy
```

---

## Design Decisions

**Why not Azure Firewall on day one?**
At ~$950/mo it's the single biggest cost item in any landing zone. A B-series router VM with IP forwarding does the same job for $8/mo while you validate architecture, onboard workloads, and build confidence in the design. Phase 2 OPNsense at $118/mo gives you full firewall capability. Azure Firewall is available as Phase 3 if compliance ever mandates it.

**Why AVNM instead of manual peerings?**
Adding a new spoke is one `terraform apply` — drop a new VNet ID into the AVNM network group and peerings, security admin rules, and routing (Phase 2) propagate automatically. No spoke Terraform ever changes.

**Why shared private DNS zones?**
8 zones created once in management, linked to every spoke. Private endpoint FQDNs resolve to private IPs from any spoke without duplication.

**Why hub-and-spoke instead of flat VNet?**
East-west traffic inspection, centralised egress via shared NAT GW, future VPN/ExpressRoute via GatewaySubnet, Bastion via BastionSubnet — all pre-declared at zero cost in the hub.
