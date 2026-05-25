---
description: Orchestrate publishing a deployed Foundry agent to Microsoft Teams / M365 Copilot — preflight, identity-flip handling, RBAC re-fan, and M365 admin approval runbook. Closes TD-2.
input:
  - agent_path: "Path to the agent folder (e.g. agents/learn-agent)"
  - agent_name: "The deployed agent name (e.g. learn-agent)"
  - bot_app_id: "Bot Framework Entra app ID (optional — discovered from agent-capabilities.yaml workiq_teams.bot_app_id)"
  - m365_admin_runbook_only: "true|false — when true, skip publish + RBAC re-fan; only (re-)emit the M365 admin approval runbook from existing publish state. Useful if the admin lost the original message. Default false."
mcp:
  - azure
  - foundry
---

# Publish to Teams / M365 Copilot: ${input:agent_name}

Use **foundry-teams-workiq** (publish-flow.md), **foundry-identity** (post-publish RBAC re-fan rationale), **foundry-evals** + **foundry-purview** (publish gates). Stamps the `publish` block in `agent-status.json` (schema: [agent-status-schema.md § publish](../skills/foundry-deploy/agent-status-schema.md#publish--written-by-publish-teams-and-configure-rbac---post-publish-td-2)).

> **Why this is a discrete prompt.** Publishing changes the agent's runtime identity from the project identity to a Bot Framework application identity. Per MS Learn: *"Tool calls authenticated by agent identity use the application identity after publishing, not the project identity."* ([Publish your agent as an Agent Application](https://learn.microsoft.com/azure/foundry/agents/how-to/agent-applications)) Capability grants made by `/configure-rbac` against the project identity break silently unless re-fanned to the application identity. This prompt orchestrates that re-fan + the M365 admin approval handoff.

## Step 0 — Mode short-circuit

If `${input:m365_admin_runbook_only} == "true"`: jump directly to **Step 7**.

## Step 0a — Inbound chain branch (private Foundry)

Before preflight, check whether the agent runs in a private-network configuration. If so, the published Bot Service messaging endpoint must point at a customer-owned reverse proxy (APIM v2 / YARP / AppGW+APIM) — **not** at the Foundry FQDN directly, because Bot Framework calls land from the public backbone on IPs that cannot reach a `publicNetworkAccess=Disabled` Foundry account. This is the silent-publish-success failure mode and is the reason [TD-23](../../TECHNICAL_DEBT.md#td-23--inbound-firewall-coverage-for-teams--m365-copilot--private-foundry-agent) exists.

Read `agent-capabilities.yaml` `network.class` and (if `agent-status.json` has been stamped by `/prepare-deploy`) `network.foundry.public_network_access`:

```bash
NETWORK_CLASS=$(jq -r '.network.class // "public"' \
  ${input:agent_path}/agent-status.json 2>/dev/null)
FOUNDRY_PNA=$(jq -r '.network.foundry.public_network_access // "Enabled"' \
  ${input:agent_path}/agent-status.json 2>/dev/null)
```

If `NETWORK_CLASS == "byo_vnet"` **or** `FOUNDRY_PNA == "Disabled"`, print this branch banner to the operator and proceed to Step 1 (do NOT skip — the preflight gates still apply):

```
[!] Private Foundry detected (network.class=$NETWORK_CLASS, publicNetworkAccess=$FOUNDRY_PNA).

    Bot Framework Channel Adapter calls land from public Microsoft backbone
    on the Teams service tag — they CANNOT reach a private Foundry endpoint
    directly. You must front the agent with a reverse proxy that validates
    the Bot Framework JWT and routes outbound to the Foundry PE.

    READ FIRST:
    .agents/skills/foundry-teams-workiq/inbound-firewall.md

    Shipped paste-ready scaffold (APIM v2 + VNet integration):
    .agents/skills/foundry-teams-workiq/scripts/templates/apim-v2-vnet-integrated.bicep

    After the inbound chain is deployed, configure the Bot Service messaging
    endpoint at https://<your-apim-custom-domain>/messages — NOT the Foundry FQDN.
    Verify with:
      .agents/skills/foundry-teams-workiq/scripts/probe-inbound-chain.sh \
        ${input:agent_path} <your-apim-custom-domain> --stamp

    Preflight gate BYO_VNET_PUBLIC_BOT_MISMATCH will still fire in Step 2 —
    once you've stood up the inbound chain, override the gate with documented
    exception and re-run.
```

If the network class is public, skip the banner and proceed.

## Step 1 — Detect agent object model

```python
agent = mcp_foundry_mcp_agent_get(agent_name="${input:agent_name}")
identity_model = "new" if agent.get("identity") else "legacy"
```

Print the verdict. The two branches diverge after this step:

- **`new` model:** continue through Steps 2–8 below.
- **`legacy` model:** print the [`teamsapp` runbook from foundry-teams-workiq/SKILL.md § Channel publishing](../skills/foundry-teams-workiq/SKILL.md#channel-publishing--post-deploy-steps-print-to-user), stamp `publish.agent_identity_model = "legacy"` and `publish.channel = "msteams-legacy"`, then STOP. The new-model orchestration is structurally unavailable until the upstream upgrade gesture GAs ([TD-2 verification note](../../TECHNICAL_DEBT.md#td-2--teams-publish-orchestration-scope-shifted--original-gap-obsoleted-upstream-new-gap-declared)).

## Step 2 — Preflight (hard gates)

Run [`preflight-publish.sh`](../skills/foundry-teams-workiq/scripts/preflight-publish.sh). It emits `KEY=VALUE` on stdout and the hard verdict on stderr; non-zero exit means a gate failed.

```bash
bash .agents/skills/foundry-teams-workiq/scripts/preflight-publish.sh \
  ${input:agent_path} ${input:agent_name} ${input:bot_app_id}
```

Gates checked (full reference: [publish-flow.md § Step 1](../skills/foundry-teams-workiq/publish-flow.md#step-1--preflight-script-driven)):

| Gate | Failure recovery |
|---|---|
| `BOT_SERVICE_RP_REGISTERED=true` | `az provider register -n Microsoft.BotService` (subscription-Owner required) |
| `BYO_VNET_PUBLIC_BOT_MISMATCH=false` | Document the exception; private-endpoint Bot Service path is out of scope |
| `EVALS_CONTINUOUS_RULE_ID` non-empty | Run `/setup-evals` with `include_scheduled=true` (or at minimum the continuous rule) |
| `PURVIEW_ENABLED=true` | Run `/setup-purview` |
| `PUBLISH_METADATA_SECRET_SCAN=clean` | Scrub the matched field in `agent-capabilities.yaml` (the wrapper prints which fields hit), re-run preflight |

If any hard gate fails, STOP with the preflight stderr verdict — do not advance to Step 3.

## Step 3 — Patch agent.yaml authorization scheme

For new-model agents, the runtime needs `BotServiceRbac` authorization and Activity protocol enabled. Patch `${input:agent_path}/agent.yaml` (idempotent YAML merge — leave existing keys intact):

```yaml
authorization:
  schemes:
    - type: BotServiceRbac
activity_protocol:
  enabled: true
```

Verify the patch by re-parsing the YAML. If the file already had these keys with matching values, this step is a no-op.

## Step 4 — Print the publish command

The publish event is mutating and remains operator-visible. Print the exact CLI line; do NOT execute it on behalf of the operator.

```bash
azd ai agent publish \
  --agent-name ${input:agent_name} \
  --channel msteams \
  --bot-app-id ${input:bot_app_id}
```

Wait for the operator to confirm publish completed (they paste the CLI output back).

## Step 5 — Capture the identity flip

Re-read the agent to get the application identity principal ID:

```bash
APP_PRINCIPAL=$(az rest --method get \
  --uri "$PROJECT_ENDPOINT/agents/${input:agent_name}?api-version=2025-05-01" \
  --query 'identity.applicationPrincipalId' -o tsv)
```

Stamp the publish event:

```bash
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path ${input:agent_path} \
  --section publish \
  --json "{
    \"channel\":\"msteams\",
    \"published_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"bot_app_id\":\"${input:bot_app_id}\",
    \"application_identity_principal_id\":\"$APP_PRINCIPAL\",
    \"agent_identity_model\":\"new\",
    \"preflight\":{
      \"bot_service_rp_registered\":true,
      \"byo_vnet_public_bot_mismatch\":false,
      \"evals_continuous_rule_id\":\"$EVALS_CONTINUOUS_RULE_ID\",
      \"purview_enabled\":true
    },
    \"publish_metadata_secret_scan\":\"clean\",
    \"m365_admin_approval_status\":\"pending\"
  }"
```

If `$APP_PRINCIPAL` comes back empty: publish likely did not complete; STOP and ask the operator to re-check the `azd ai agent publish` output.

## Step 6 — Post-publish RBAC re-fan

Run the helper to verify state and print the exact `/configure-rbac` invocation:

```bash
bash .agents/skills/foundry-teams-workiq/scripts/refan-rbac-post-publish.sh \
  ${input:agent_path} ${input:agent_name}
```

Then dispatch:

```
/configure-rbac agent_path=${input:agent_path} agent_name=${input:agent_name} post_publish=true
```

`/configure-rbac --post-publish` skips Phase 1/2 and re-fans Phase 3 capability grants against `publish.application_identity_principal_id`. Writes to `rbac.capability_grants_post_publish` (preserves pre-publish state for audit). Stamps `publish.rbac_refanned_at` on completion. See [configure-rbac § Step 3 — Re-fan mode](configure-rbac.prompt.md#step-3--phase-3-capability-aware-grants) and [publish-flow.md § Step 6](../skills/foundry-teams-workiq/publish-flow.md#step-6--post-publish-rbac-re-fan).

> **Propagation reminder.** AAD role assignments take 5–15 minutes to propagate. If the operator tests an `@mention` immediately and gets a 403, that is expected — re-test after 15 minutes.

## Step 7 — Emit the M365 admin approval runbook

Compose the runbook from `agent-status.json` so it always reflects the current state (works both right after publish and in `m365_admin_runbook_only` re-emit mode):

```bash
EVALS_RULE=$(jq -r '.evals.continuous_rule_id' ${input:agent_path}/agent-status.json)
NETWORK_CLASS=$(jq -r '.network.class // "public"' ${input:agent_path}/agent-status.json)
LAST_VERIFY=$(jq -r '.verify.last_run_at // "never"' ${input:agent_path}/agent-status.json)
APP_PRINCIPAL=$(jq -r '.publish.application_identity_principal_id' ${input:agent_path}/agent-status.json)
BOT_APP_ID=$(jq -r '.publish.bot_app_id' ${input:agent_path}/agent-status.json)
```

Print this paste-ready message to the operator (full template in [publish-flow.md § Step 7](../skills/foundry-teams-workiq/publish-flow.md#step-7--emit-the-m365-admin-approval-runbook)):

```markdown
# Subject: Approve Foundry agent "${input:agent_name}" for Microsoft 365 / Teams publish

Hi <admin>,

I've published the Foundry agent **${input:agent_name}** to the Microsoft.BotService channel.
Before users can `@mention` it in Teams or summon it from M365 Copilot, please approve from:

1. https://admin.microsoft.com → Settings → Integrated apps → "Pending approval"
2. Locate `${input:agent_name}` (Bot App ID: $BOT_APP_ID) → Review.
3. Assignment scope: People in your organization (or a pilot group).
4. Approve. Propagation: 30 min typical, up to 24 h.

Governance attestation:
- Continuous eval rule:  $EVALS_RULE
- Purview middleware:    enabled
- Network class:         $NETWORK_CLASS
- Last verify pass:      $LAST_VERIFY

Run-as identity after publish: $APP_PRINCIPAL
(Per MS Learn: tool calls now use the application identity, not the project identity.)

Reply with approval timestamp and I'll stamp it.
```

Stamp emit time:

```bash
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path ${input:agent_path} \
  --path 'publish.m365_admin_approval_runbook_emitted_at' \
  --json "\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
```

Tell the operator: once the admin replies with the approval timestamp, run:

```bash
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path ${input:agent_path} \
  --path 'publish.m365_admin_approval_status' \
  --json '"approved"'
```

## Step 8 — Announce next-step verification

Print:

> Publish flow complete. Run `/verify-agent` in ~15 minutes to confirm:
> - AAD propagation of the re-fanned grants (capability tools should succeed under the application identity)
> - Agent appears in WorkIQ / Agent 365 inventory once M365 admin approves
> - First Teams `@mention` produces an OTel trace tagged `channel=Teams` (see [foundry-teams-workiq/SKILL.md § V3](../skills/foundry-teams-workiq/SKILL.md#v3-invocation-trace))

If publish was previously stamped (re-run scenario), additionally print the diff between
`rbac.capability_grants` and `rbac.capability_grants_post_publish` so the operator can
sanity-check what changed.

## Failure modes specific to this prompt

See [foundry-teams-workiq/publish-flow.md § Failure modes specific to publish](../skills/foundry-teams-workiq/publish-flow.md#failure-modes-specific-to-publish).
