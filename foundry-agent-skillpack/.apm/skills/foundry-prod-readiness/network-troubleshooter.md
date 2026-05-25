# Network Troubleshooter — Foundry Hosted Agent

Step-by-step runbook for converting unknown network failures (silent timeouts, mysterious 503s, "tool span missing" with no exception) into a known failure mode with a documented fix.

> **When to use this.** The agent deployed cleanly. `azd up` succeeded. But invocations return 503 / time out / show no `execute_tool` spans even though the same code worked locally. The fast path scripts ([`check-source-network.sh`](scripts/network/check-source-network.sh) etc.) said ✅. Something between the agent and a data source / Foundry / Internet is wrong. Use this runbook in order — each step narrows the suspect surface.
>
> **Tracked:** [TD-10](../../../TECHNICAL_DEBT.md#td-10) Layer 3 (deep-network).

---

## Symptom triage

| Observed | Probably |
|---|---|
| Agent returns `503` immediately, no token stream | Egress blocked at NSG / Firewall / SEP — go to [Step 2](#step-2--rerun-detection-with---deep) |
| Agent returns `404` or `BadRequest` on the first tool call only | Per-source PE missing or not Approved — go to [Step 3](#step-3--per-source-private-endpoint-state) |
| Agent works for some sources, times out for one | Private DNS zone not linked OR resolves to the public IP — go to [Step 4](#step-4--dns-resolution-from-inside-the-vnet) |
| Agent works in portal, fails when invoked from Teams | Bot Service endpoint mismatch (NOT this runbook — see [foundry-teams-workiq § Channel publishing](../foundry-teams-workiq/SKILL.md)) |
| Teams `@mention` shows typing indicator → never replies (private Foundry) | Inbound chain misconfigured (no JWT-validating reverse proxy in front of the private agent) OR outbound reply FQDNs (`smba.trafficmanager.net`, `login.botframework.com`) blocked at egress firewall — → [foundry-teams-workiq/inbound-firewall.md](../foundry-teams-workiq/inbound-firewall.md) |
| `nslookup` returns a public IP from inside the VNet | DNS zone linkage gap — go to [Step 4](#step-4--dns-resolution-from-inside-the-vnet) |
| Random 5xx with no pattern | NOT a network issue. Check `/troubleshoot symptom="random 5xx"` or [foundry-failure-modes](../foundry-failure-modes/SKILL.md) |

---

## Step 1 — Identify the network class

```bash
.agents/skills/foundry-prod-readiness/scripts/network/check-foundry-network-mode.sh \
  <subscription_id> <rg> <foundry_account> <acr_name>
```

Read the `FOUNDRY_NETWORK_CLASS=` line:

- **`public`** — there should be no network-side block. If you're seeing 503s, this runbook is the wrong rabbit-hole; jump to [foundry-failure-modes](../foundry-failure-modes/SKILL.md).
- **`managed_vnet`** — Microsoft owns the VNet. NSG / Firewall walks below don't apply (you can't inspect Microsoft's subnet). Skip to [Step 3](#step-3--per-source-private-endpoint-state) and [Step 4](#step-4--dns-resolution-from-inside-the-vnet).
- **`byo_vnet`** — you own the subnet. All steps apply.

---

## Step 2 — Re-run detection with `--deep`

Run the deep variant of source-network detection for each affected source. The `--deep` flag opts into the three new walkers:

```bash
# Pull the agent subnet from agent-capabilities.yaml network.byo_vnet.subnet_id
AGENT_SUBNET=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/agent-subnet

# Optional: pull the firewall id if you have an Azure Firewall in the route path
FIREWALL_ID=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/azureFirewalls/<fw>

# Canonical Foundry / source FQDNs to allowlist-check against Firewall rules
.agents/skills/foundry-prod-readiness/scripts/network/check-source-network.sh \
  /subscriptions/<sub>/.../Microsoft.Search/searchServices/kb-prod \
  --deep "$AGENT_SUBNET" "$FIREWALL_ID" \
    login.microsoftonline.com \
    <foundry_account>.services.ai.azure.com \
    kb-prod.search.windows.net
```

Inspect the deep keys at the end of the output:

- `DEEP_NSG_VERDICT=deny` — outbound 443 is blocked at the NSG. Add an Allow rule or use a less restrictive service tag. The verdict line cites the matching rule by name.
- `DEEP_FIREWALL_MISSING_FQDNS=<csv>` — the listed FQDNs are not in any application rule of the Firewall policy. Add a rule with the missing targetFqdns OR cover them with an FQDN tag (e.g. `AzureActiveDirectory`).
- `DEEP_SEP_FOUNDRY_AFFECTED=true` — a Service Endpoint Policy on the subnet scopes Microsoft.CognitiveServices and your Foundry account isn't in the allowed list. Extend the SEP or remove it.

You can also run the individual scripts directly:

```bash
.agents/skills/foundry-prod-readiness/scripts/network/deep-walk-nsg.sh "$AGENT_SUBNET" <fqdn> [<fqdn> ...]
.agents/skills/foundry-prod-readiness/scripts/network/deep-walk-firewall.sh "$FIREWALL_ID" <fqdn> [<fqdn> ...]
.agents/skills/foundry-prod-readiness/scripts/network/check-service-endpoint-policy.sh "$AGENT_SUBNET"
```

Each one prints a machine-readable block and a human verdict; the prompts use the machine block for state, you read the verdict.

---

## Step 3 — Per-source Private Endpoint state

```bash
.agents/skills/foundry-prod-readiness/scripts/network/check-private-endpoint.sh \
  /subscriptions/<sub>/.../<resource>
```

Look for `PE_STATUS=`:

- `Approved` — good; continue to [Step 4](#step-4--dns-resolution-from-inside-the-vnet).
- `Pending` — needs approval. Caller needs `Contributor` or `Owner` on the *target* resource OR on the Foundry account (per side). Often two different humans → emit the runbook with [`runbook-emit.sh`](../foundry-roles/scripts/runbook-emit.sh).
- `Rejected` / `Disconnected` — delete the PE and recreate. Inspect the PE in the portal for the rejection reason first.
- `none` — no PE exists. If the source has `publicNetworkAccess=Disabled`, the agent cannot reach it. Provision a PE (paste-ready scaffold: [scripts/network/templates/byo-vnet-with-pe.bicep](scripts/network/templates/byo-vnet-with-pe.bicep) for the agent side; data-source PEs live in those resources' own templates).

---

## Step 4 — DNS resolution from inside the VNet

This is the **#1 silent failure**. PE exists, status Approved, but `<resource>.<service>.windows.net` resolves to a *public* IP because the matching `privatelink.<service>.windows.net` private DNS zone isn't linked to the agent's VNet.

```bash
.agents/skills/foundry-prod-readiness/scripts/network/check-private-dns.sh \
  <vnet_rg> <vnet_name>
```

Verifies each expected `privatelink.*` zone is linked to the VNet. Missing zones → use the [BYO VNet + PE Bicep scaffold](scripts/network/templates/byo-vnet-with-pe.bicep) as a reference for the right zone names and link pattern.

Then, to confirm end-to-end, `nslookup` from inside the VNet — but Foundry's egress IP is dynamic and unreachable, so use a **Bastion host** in the same VNet:

```
# From a Bastion-connected VM in the agent's VNet:
nslookup <foundry_account>.services.ai.azure.com
# Expected: a private IP in your VNet's address space (10.x.x.x).
# If you see a public IP: the privatelink.services.ai.azure.com zone is not linked.
```

---

## Step 5 — Confirm fix and re-baseline

After applying the fix, re-run the fast path and the deep path:

```bash
# Fast path (every source)
.agents/skills/foundry-prod-readiness/scripts/network/check-source-network.sh <resource_id>

# Deep path (only the previously-failing source)
.agents/skills/foundry-prod-readiness/scripts/network/check-source-network.sh <resource_id> \
  --deep "$AGENT_SUBNET" "$FIREWALL_ID" <fqdn> [<fqdn> ...]
```

Then re-stamp `agent-status.json`:

```bash
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path <agent_path> \
  --section network \
  --json '{"sources":{"<resource_id>":{"verdict":"reachable_via_pe","deep_verdict":"pass","checked_at":"<now>"}}}'
```

Finally re-run `/verify-agent` to confirm tool spans now appear.

---

## When to escalate (not this runbook)

- **Cross-tenant ExpressRoute / on-prem peering** — these need network-team support; out of scope here.
- **Unresolvable Bastion host setup** — provision a small jumpbox in the VNet first; otherwise DNS verification is impossible.
- **Foundry-side PE stuck Pending > 24 hours after approval** — open a support ticket; the platform's PE approval can stall and we have no diagnostic surface for it.

---

## Hand-off artifacts

When detection finds a problem but you (the caller) lack rights to fix it, emit a runbook for the privileged human:

```bash
.agents/skills/foundry-roles/scripts/runbook-emit.sh network-fix \
  <action> <scope> <required_role>
```

This is the **runbook-emit, don't escalate** pattern — we never request elevation in-band; we hand off a paste-ready artifact.

---

## Cross-skill links

- Network classes + decision flow + FQDN allowlist: [networking.md](networking.md)
- Required roles for network operations: [foundry-roles/role-matrix.md Phase 4](../foundry-roles/role-matrix.md#phase-4--network-isolation-managed-vnet--byo-vnet)
- Per-source RBAC verifier: [foundry-knowledge/scripts/verify-source-rbac.sh](../foundry-knowledge/scripts/verify-source-rbac.sh)
- Known failure modes catalog: [foundry-failure-modes/SKILL.md](../foundry-failure-modes/SKILL.md)
