# Publishing a Foundry agent to Teams / M365 Copilot — full flow

> Owned by [`/publish-teams`](../../prompts/publish-teams.prompt.md). Closes [TD-2](../../../TECHNICAL_DEBT.md#td-2--teams-publish-orchestration-scope-shifted--original-gap-obsoleted-upstream-new-gap-declared).
> The customer-facing reason this is a discrete prompt: **publish changes the agent's runtime identity**. Capability grants made by `/configure-rbac` against the project identity break unless re-fanned to the application identity ([MS Learn — Plan for identity changes](https://learn.microsoft.com/azure/foundry/agents/how-to/agent-applications)).

## When to run this

After `/configure-rbac` succeeds and `/verify-agent` shows green, but **before** end users `@mention` the agent in Teams or summon it from M365 Copilot. The prompt is also safe to re-run idempotently; the `publish` block in `agent-status.json` is the cursor.

## The two object models — first branch

`mcp_foundry_mcp_agent_get(agent_name=…)` returns the agent definition. Inspect:

```jsonc
{
  "identity": {                          // NEW model — present
    "principalId": "…",
    "tenantId":    "…"
  },
  "tools": [ … ]
}
// vs
{
  "identity": null,                      // LEGACY model — null
  "tools": [ … ]
}
```

- **`identity != null` (new model):** Foundry portal vNext exposes a Direct-Publish-to-Teams gesture that auto-creates the Azure Bot Service resource and dispatches M365 admin approval. The customer-facing chore is the **identity flip** — Steps 1–6 below.
- **`identity == null` (legacy model):** Direct-Publish is unavailable until the upstream upgrade gesture GAs ("Coming soon" per MS Learn). Fall back to the [`teamsapp` runbook in SKILL.md § Channel publishing](SKILL.md#channel-publishing--post-deploy-steps-print-to-user). Skip the rest of this doc.

## Step 1 — Preflight (script-driven)

Run [`scripts/preflight-publish.sh`](scripts/preflight-publish.sh):

```bash
.agents/skills/foundry-teams-workiq/scripts/preflight-publish.sh \
  <agent_path> <agent_name> [<bot_app_id>]
```

It writes `KEY=VALUE` to stdout and exits non-zero on a hard gate failure. Keys checked:

| Key | Required value | Gate |
|---|---|---|
| `BOT_SERVICE_RP_REGISTERED` | `true` | hard — required before BotService channel can be created |
| `AGENT_IDENTITY_MODEL` | `new` or `legacy` | informational — drives branch |
| `BYO_VNET_PUBLIC_BOT_MISMATCH` | `false` | hard — Bot Service is public-only today; BYO-VNet agents need a documented exception |
| `EVALS_CONTINUOUS_RULE_ID` | non-empty | hard — publish without continuous eval is a governance failure (TD-2 spec) |
| `PURVIEW_ENABLED` | `true` | hard — Purview middleware must be on before audit reaches M365 surfaces |
| `PUBLISH_METADATA_SECRET_SCAN` | `clean` | hard — display name / description / endpoint URLs scanned for accidental tokens |

The two hard gates that come up most often (`EVALS_CONTINUOUS_RULE_ID` empty and `PURVIEW_ENABLED=false`) point the operator at `/setup-evals continuous` and `/setup-purview`, respectively. The prompt does not auto-run them; this is a deliberate boundary.

## Step 2 — Configure the `agent.yaml` authorization scheme

For new-model agents, the runtime needs `BotService` (or `BotServiceRbac`) as the authorization scheme, and the activity protocol must be enabled. Update `agent.yaml` in `<agent_path>`:

```yaml
# agent.yaml
authorization:
  schemes:
    - type: BotServiceRbac        # preferred; BotService is the legacy form
activity_protocol:
  enabled: true
```

`/publish-teams` patches this in place (idempotent — does nothing if already present). The patch is a YAML merge, not a string replace, so existing keys survive.

## Step 3 — Trigger the publish

For new-model agents, publish via Foundry portal **or** the `azd ai agent publish` CLI gesture (whichever the operator prefers). The prompt prints the exact CLI command and does not run it for you — the publish event is mutating and should remain operator-visible.

```bash
azd ai agent publish \
  --agent-name <agent_name> \
  --channel msteams \
  --bot-app-id <bot_app_id>
```

(For legacy agents, the prompt falls back to the [`teamsapp` runbook](SKILL.md#channel-publishing--post-deploy-steps-print-to-user).)

## Step 4 — Capture the identity flip

After publish completes, re-read the agent:

```bash
APP_PRINCIPAL=$(az rest --method get \
  --uri "https://<foundry>.services.ai.azure.com/api/projects/<project>/agents/<agent_name>?api-version=2025-05-01" \
  --query 'identity.applicationPrincipalId' -o tsv)
```

Stamp into `agent-status.json`:

```bash
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path <agent_path> \
  --section publish \
  --json "{
    \"channel\":\"msteams\",
    \"published_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"bot_app_id\":\"<bot_app_id>\",
    \"application_identity_principal_id\":\"$APP_PRINCIPAL\",
    \"agent_identity_model\":\"new\"
  }"
```

The schema is documented in [foundry-deploy/agent-status-schema.md § `publish`](../foundry-deploy/agent-status-schema.md#publish--written-by-publish-teams-and-configure-rbac---post-publish-td-2).

## Step 5 — Scan publish metadata for accidental secrets

[`preflight-publish.sh`](scripts/preflight-publish.sh) already does this in Step 1, but the prompt re-runs the scan post-publish in case display-name overrides changed between preflight and publish. Findings (any match against the regex set) block: re-publish after the operator scrubs them.

Regex set (in `preflight-publish.sh`, kept centralized for testability):

- AAD client secrets: `[A-Za-z0-9~._\-]{34,}~[A-Za-z0-9~._\-]{3,}`
- AAD app passwords: `[A-Za-z0-9_\-]{36,}`  (length-only — last line of defense)
- Bearer tokens: `eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}`
- Connection strings: `(AccountKey|SharedAccessKey|InstrumentationKey)=`

## Step 6 — Post-publish RBAC re-fan

This is the actual point of `/publish-teams`. Run `/configure-rbac --post-publish`:

```bash
/configure-rbac agent_path=<agent_path> agent_name=<agent_name> post_publish=true
```

What changes versus a normal `/configure-rbac` run:

- **Skips Phase 1 / Phase 2.** The base two-identity matrix (project identity + ACR pull principal) is unaffected by publish.
- **Re-runs Phase 3** with `TARGET_PRINCIPAL=<publish.application_identity_principal_id>` from `agent-status.json`.
- **Skips `fabric` and `purview` capability rows.** Fabric data agent grants target the project; Purview toggle is account-scoped. Neither moves under the application identity.
- **Writes to `rbac.capability_grants_post_publish`** instead of overwriting `rbac.capability_grants` — the pre-publish state is preserved for audit / rollback.
- **Stamps `publish.rbac_refanned_at`** on success.

## Step 7 — Emit the M365 admin approval runbook

The prompt prints a paste-ready runbook for the M365 / Teams admin:

```markdown
# Subject: Approve Foundry agent "<agent_name>" for Microsoft 365 / Teams publish

Hi <admin>,

I've published the Foundry agent **<agent_name>** to the Microsoft.BotService channel.
Before users can `@mention` it in Teams or summon it from M365 Copilot, you'll need to
approve it from the Microsoft 365 admin center:

1. Sign in: https://admin.microsoft.com → Settings → Integrated apps → "Pending approval"
2. Locate `<agent_name>` (Bot App ID: <bot_app_id>) → Review.
3. Assignment scope: **People in your organization** (or a pilot group if preferred).
4. Approve. Propagation: typically 30 min, can take up to 24 h.

Governance attestation (so you don't have to ask):

- Continuous eval rule:  <evals_continuous_rule_id>  (gate enforced pre-publish)
- Purview middleware:    enabled                      (gate enforced pre-publish)
- Network class:         <network.class>              (from agent-capabilities.yaml)
- Last verify pass:      <verify.last_run_at>         (from agent-status.json)

Run-as identity after publish: <publish.application_identity_principal_id>
(Per MS Learn: "Tool calls authenticated by agent identity use the application
identity after publishing, not the project identity.")

Reply with approval timestamp and I'll stamp it in our agent-status ledger.
```

Stamp `publish.m365_admin_approval_runbook_emitted_at` immediately after printing. Stamp `publish.m365_admin_approval_status` once the admin confirms (operator runs `agent_status.py update --path 'publish.m365_admin_approval_status' --json '"approved"'`).

## Failure modes specific to publish

| Symptom | Root cause | Fix |
|---|---|---|
| Publish CLI returns 409 with "BotService not registered" | Step 1 `BOT_SERVICE_RP_REGISTERED=false` skipped | `az provider register -n Microsoft.BotService` (subscription-Owner required) |
| Publish succeeds; Teams `@mention` returns "Sorry, something went wrong" | M365 admin approval (Step 7) not granted yet | Wait or escalate to admin |
| Capability tools that worked pre-publish now 403 from Teams invocations | Step 6 (`/configure-rbac --post-publish`) not run | Run it; wait 5–15 min for AAD propagation |
| `BYO_VNET_PUBLIC_BOT_MISMATCH=true` blocks publish | Agent is on BYO-VNet; Bot Service is public-egress only today | Stand up the inbound chain per [inbound-firewall.md](inbound-firewall.md) (APIM v2 + VNet integration, paste-ready Bicep), point the Bot Service messaging endpoint at the APIM custom domain, then override the gate with documented exception |
| Display-name secret-scan finds a match | An accidental token landed in `agent-capabilities.yaml` → `publish.display_name` | Scrub the YAML, re-run `/publish-teams` |

## Do NOT

- **Do NOT** rotate `bot_app_id` mid-flow. The `publish.bot_app_id` field is the cursor for re-runs; rotating it invalidates the runbook trail.
- **Do NOT** skip Step 6. Pre-publish grants will break silently — the symptom is "agent worked yesterday, 403s today", which is the worst possible support ticket.
- **Do NOT** assume the M365 admin's approval propagates instantly. The runbook explicitly warns "up to 24 h" for a reason.
- **Do NOT** treat the legacy and new branches as a strict choice for the operator. If `identity == null`, the new branch is structurally unavailable — re-running the prompt won't unlock it. Wait for the upstream upgrade gesture.
