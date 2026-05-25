# Foundry Hosted Agent — Networking

> Validity date: 2026-05-14. Foundry preview-adjacent — re-verify against [Configure managed virtual network](https://learn.microsoft.com/azure/foundry/how-to/managed-virtual-network), [Set up private networking for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks), and [How to configure network isolation](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link) before relying on the matrices below.

Three deployment classes. Pick before `azd up` — outbound network mode **cannot be reconfigured** after deploy without redeploying Foundry.

| Class | Inbound | Outbound | When to pick |
|---|---|---|---|
| **Public** | Public | Public | Sandbox / dev. Fastest start. No data classification. |
| **Managed VNet** | Public (PNA flag-controlled) | Microsoft-managed VNet with managed PEs to Azure resources | Default for prod. Microsoft owns the VNet; you don't see NICs in your subscription. |
| **BYO VNet (Standard Setup with private networking)** | Private endpoint into your VNet | Subnet-injected (Microsoft.App/environments delegation, /27+) into your VNet | Regulated workloads needing data residency, customer-controlled egress, or `Allow only approved outbound`. |

## Managed VNet outbound modes

Set at account creation. **Only narrowing transitions are allowed** post-creation.

| Mode | Behavior | Allowed transitions |
|---|---|---|
| `Allow internet outbound` | All outbound to internet permitted | → cannot move to "Allow only approved" later |
| `Allow only approved outbound` | Service tags + managed PEs + optional FQDN allowlist via Azure Firewall (ports 80, 443) | → cannot move back to "Allow internet" |
| `Disabled` | Managed VNet not enabled (use BYO VNet or stay public) | → can enable managed VNet later |

## Tools and protocols by network class — what works where

From [outbound network isolation walkthrough](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link#set-up-walkthrough-for-outbound-network-isolation).

| Tool / capability | Network-isolated agent | Traffic flow |
|---|---|---|
| MCP Tool (private MCP) | ✅ | Through your VNet subnet |
| Azure AI Search | ✅ | Through PE |
| Code Interpreter | ✅ | Microsoft backbone |
| Function Calling | ✅ | Microsoft backbone |
| Bing Grounding | ✅ | Public endpoint (won't satisfy "all-private" mandates) |
| Web search | ✅ | Public endpoint |
| SharePoint Grounding | ✅ | Public endpoint |
| Foundry IQ (preview) | ✅ | Via MCP |
| OpenAPI tool | ✅ | Through your VNet subnet |
| Azure Functions | ✅ | Through your VNet subnet |
| Agent-to-Agent (A2A) | ✅ | Through your VNet subnet |
| **Fabric Data Agent** | **❌** | Fabric workspace-level private link is unsupported — Fabric resource MUST be public |
| Logic Apps | ❌ Under development | — |
| File Search | ❌ Under development | — |
| Browser Automation | ❌ Under development | — |
| Computer Use | ❌ Under development | — |
| Image Generation | ❌ Under development | — |

## Critical gotchas (the ones that silently break deploys)

1. **ACR must be public-network-enabled** even for private Foundry. Public-access-disabled ACR with PE is **not yet supported** for hosted agents. ([limitations](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link#limitations-and-considerations))
2. **No outbound network reconfiguration post-deploy.** Subnet delegation and VNet injection are immutable. Plan up-front.
3. **Don't use `172.17.0.0/16`** for your VNet — Docker bridge collision.
4. **PEs to Storage / AI Search / Cosmos are NOT auto-created.** You create them in those resources' own pages. Foundry deploy will not provision them for you.
5. **Private endpoints stuck `Pending`.** Caller needs `Contributor` or `Owner` on the Foundry account to approve from Foundry-side. Caller needs `Contributor`/`Owner` on the *target* resource to approve from target-side. Often two different humans → runbook emit.
6. **DNS misresolution** is the #1 silent failure. `nslookup <foundry-fqdn>` from inside the VNet must return a `10.x.x.x` private IP. If it returns a public IP, the right `privatelink.<service>.<region>.<svc>.windows.net` private DNS zone isn't linked to your VNet.

## Required roles for network operations

See [foundry-roles/role-matrix.md Phase 4](../foundry-roles/role-matrix.md#phase-4--network-isolation-managed-vnet--byo-vnet). Quick reference:

| Action | Role | Scope |
|---|---|---|
| Read network configuration of any resource | `Reader` | resource (floor for all detection scripts) |
| Approve managed PE (Foundry side) | `Azure AI Enterprise Network Connection Approver` | target resource (granted to Foundry account MI) |
| Approve PE on target resource | `Contributor` or `Owner` | target |
| Create / modify VNet, subnet, NSG | `Network Contributor` | VNet RG |
| Link private DNS zone | `Network Contributor` | DNS zone + VNet |

## Detection scripts (Reader required)

| Script | What it answers | Required role |
|---|---|---|
| [check-foundry-network-mode.sh](scripts/network/check-foundry-network-mode.sh) | What network class is this Foundry account in? + ACR public-access flag | `Reader` on Foundry account + ACR |
| [check-source-network.sh](scripts/network/check-source-network.sh) | Is this resource reachable from a Foundry agent in network class X? (`--deep` walks NSG / Firewall / SEP — see below) | `Reader` on the resource (+ VNet / Firewall in `--deep` mode) |
| [check-private-endpoint.sh](scripts/network/check-private-endpoint.sh) | Are PEs on this resource Approved? Pending? Rejected? | `Reader` on the resource |
| [check-private-dns.sh](scripts/network/check-private-dns.sh) | Is the right private DNS zone linked to the agent's VNet? | `Reader` on the VNet's RG |
| [deep-walk-nsg.sh](scripts/network/deep-walk-nsg.sh) | Does the NSG on `<subnet>` allow outbound TCP/443? (declared + effective rules) | `Reader` on the VNet |
| [deep-walk-firewall.sh](scripts/network/deep-walk-firewall.sh) | Do the Azure Firewall application rules cover the canonical Foundry / source FQDNs? | `Reader` on the Firewall (+ policy) |
| [check-service-endpoint-policy.sh](scripts/network/check-service-endpoint-policy.sh) | Are SEPs on `<subnet>` scoping Foundry / Storage / AI Search service tags? | `Reader` on the VNet |

The four fast-path scripts (top 4) compose: `/prepare-deploy` runs them in sequence and aggregates a verdict. None mutate state; all degrade to a checklist if `Reader` is missing (per [foundry-roles](../foundry-roles/SKILL.md) preflight rules).

The three deep walkers are opt-in via `--deep` (or invokable directly). They add 60–120 s typical and require additional `Reader` scope on the VNet / Firewall. Use them when the fast path returns ✅ but invocations still fail at runtime — see [network-troubleshooter.md](network-troubleshooter.md) for the full triage flow.

## What the detection scripts deliberately leave to humans

- **Provisioning.** We never run `az network create`, `az network vnet subnet update`, or any other mutating command. When detection finds a structural gap (missing PE, missing private DNS link, BYO VNet not yet provisioned), we hand off a paste-ready Bicep scaffold at [scripts/network/templates/byo-vnet-with-pe.bicep](scripts/network/templates/byo-vnet-with-pe.bicep) — you drop it into `./infra/` and `azd up` owns the actual deploy.
- **Cross-tenant peering / ExpressRoute path verification.** Out of scope. Network teams own these.
- **DNS resolution from inside the agent's egress.** Foundry's egress IP is dynamic; we can't `nslookup` from there. Print the manual Bastion step instead (see [network-troubleshooter.md § Step 4](network-troubleshooter.md#step-4--dns-resolution-from-inside-the-vnet)).

## Decision flow

```
Is the agent for sandbox/dev?           → Public class. Done.
Does any data source have publicNetworkAccess=Disabled?
                                        → BYO VNet OR managed VNet + managed PEs.
Does the workload need Fabric Data Agent?
                                        → MUST stay public-network-enabled on Fabric side. Re-evaluate.
Need customer-controlled egress (Azure Firewall, FQDN allowlists, on-prem ExpressRoute hop)?
                                        → BYO VNet (subnet-injected) + Azure Firewall.
Otherwise (most prod cases)?            → Managed VNet + managed PEs to declared sources.
```

## Subnet sizing reference (BYO VNet)

- Delegated subnet for `Microsoft.App/environments`: **/27 minimum** (`32` IPs; `27` usable).
- Allocate per-region; don't share across Foundry accounts.
- Leave headroom — agent compute scales horizontally per session.

## Firewall allowlist (BYO VNet + Azure Firewall)

When using `Allow only approved outbound` with Azure Firewall, allowlist the FQDNs from the [trusted FQDN table](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link#firewall-allowlisting). At minimum:

| Scenario | FQDNs |
|---|---|
| Agents (always) | `*.identity.azure.net`, `login.microsoftonline.com`, `*.login.microsoftonline.com`, `*.login.microsoft.com` (or AAD service tag) |
| Evals & traces | `*.blob.core.windows.net`, `settings.sdk.monitor.azure.com` |
| Finetuning curated samples | `raw.githubusercontent.com` |
| **Bot reply path** (agent published to Teams / M365 Copilot) | `smba.trafficmanager.net`, `login.botframework.com` — the agent's outbound reply lands here; without these the user sees the typing indicator and no reply |

## Inbound — Teams / M365 Copilot → private Foundry agent

**Bot Service "Public Access" toggle is asymmetric.** Disabling it on `Microsoft.BotService/botServices/<bot>` blocks Direct Line (REST channel) only. It does **not** block the Microsoft.BotService **Channel Adapter** that delivers Teams / M365 Copilot activities — those calls land on the public Microsoft backbone via the Teams service tag (`52.112.0.0/14`, `52.122.0.0/15`) and target the messaging endpoint you registered for the bot. If your agent is on a private Foundry account (managed VNet "Allow only approved", BYO VNet, or `publicNetworkAccess=Disabled`), the Channel Adapter cannot reach the agent directly — publish succeeds silently and `@mentions` go nowhere.

Close the gap with a reverse proxy that takes the public hit, validates the Bot Framework JWT, and forwards to the Foundry PE. Definitive guide (with paste-ready APIM v2 + VNet integration Bicep):

→ [foundry-teams-workiq/inbound-firewall.md](../foundry-teams-workiq/inbound-firewall.md)

## Cross-skill references

- Per-resource RBAC for the agent identity → [foundry-identity/rbac-matrix.md](../foundry-identity/rbac-matrix.md)
- Knowledge sources affected by network class → [foundry-knowledge](../foundry-knowledge/SKILL.md) *(planned — declares per-source PE support)*
- Capability gates that branch on `network` block → [foundry-deploy/capabilities-manifest.md](../foundry-deploy/capabilities-manifest.md)
