---
name: foundry-teams-workiq
description: Microsoft Teams + WorkIQ + Agent 365 integration for Foundry agents — channel registration, MCP tooling, and lifecycle governance
---

# Foundry Teams & WorkIQ

Surfacing a Foundry agent inside Microsoft Teams (and tracking it in Agent 365 / WorkIQ) is a **post-deploy** activity. APM validates prerequisites pre-deploy and confirms registration post-deploy. Foundry's `azd up` does NOT publish your agent to Teams — that is a separate ritual.

> **For the full publish flow** (new-model agents, identity-flip handling, M365 admin approval runbook), see [publish-flow.md](publish-flow.md) and the [`/publish-teams`](../../prompts/publish-teams.prompt.md) prompt. This SKILL.md remains the reference for *consuming* Teams data as an MCP tool and for the legacy `teamsapp` packaging path.

## Router

| Topic | Read |
|---|---|
| **Full publish flow + identity-flip handling (new agent model)** | [publish-flow.md](publish-flow.md) |
| **Inbound firewall for private Foundry → Teams** (APIM v2 + JWT validation + paste-ready Bicep) | [inbound-firewall.md](inbound-firewall.md) |
| **Publish prompt** | [`/publish-teams`](../../prompts/publish-teams.prompt.md) |
| **Publish preflight script** (BotService RP + gates + secret scan) | [scripts/preflight-publish.sh](scripts/preflight-publish.sh) |
| **Post-publish RBAC re-fan wrapper** | [scripts/refan-rbac-post-publish.sh](scripts/refan-rbac-post-publish.sh) |
| **APIM v2 + VNet integration Bicep** (private-Foundry inbound) | [scripts/templates/apim-v2-vnet-integrated.bicep](scripts/templates/apim-v2-vnet-integrated.bicep) |
| **Render the APIM inbound `<validate-jwt>` policy** | [scripts/render-apim-policy.sh](scripts/render-apim-policy.sh) |
| **Probe the inbound chain end-to-end** (TLS + 401 + invalid-JWT) | [scripts/probe-inbound-chain.sh](scripts/probe-inbound-chain.sh) |
| Consume Teams data as an MCP tool (WorkIQ Teams MCP) | this file, § Wiring |
| Legacy `teamsapp` packaging path (agents with `identity == null`) | this file, § Channel publishing |

## Two distinct integrations

| Integration | What it does | Identity used | Where registered |
|---|---|---|---|
| **WorkIQ Teams MCP** (agent → Teams) | Lets the agent read Teams channel messages, send replies, etc., as a **tool** | Per-agent identity + WorkIQ MCP token | Foundry connection |
| **Teams channel publishing** (Teams → agent) | Lets users `@mention` the agent in Teams | Bot Framework app (Entra app) | Teams Admin Center + Agent 365 |

Most "Teams integration" requests mean #2 (publishing). #1 is when the agent itself needs to *consume* Teams data as a tool.

## Prerequisites — Preflight gate

Run these checks in `/prepare-deploy` Phase A when `workiq_teams.enabled: true` is in `agent-capabilities.yaml`.

### A. Tenant licensing
```bash
# Need Microsoft Agent 365 (or M365 E7 with Agent 365 add-on) in the tenant.
az rest --method get \
  --uri "https://graph.microsoft.com/v1.0/subscribedSkus" \
  --query "value[?contains(skuPartNumber, 'AGENT365') || contains(skuPartNumber, 'COPILOT_M365_AGENT')].{sku:skuPartNumber, units:prepaidUnits.enabled}" \
  -o table
```
If empty: tell the user Agent 365 licensing is required; channel publishing will fail at `Teams Admin Center → Manage agents`.

### B. Bot Framework Entra app (for channel publishing)
```bash
az ad app show --id <bot_app_id> --query '{appId:appId, displayName:displayName, signInAudience:signInAudience}'
```
Required: `signInAudience` == `AzureADMultipleOrgs` (single-tenant works only for first-party tenants).

### C. WorkIQ Teams connection (for MCP tool path)
List Foundry project connections and confirm a WorkIQ Teams connection exists:
```
mcp_foundry_mcp_project_connection_list(projectEndpoint=$EP)
```
Look for `connection_type: WorkIQTeams` (or whatever `connection_name` is in the manifest).

If absent, the user must create it via Foundry portal → Connected resources → Add → Microsoft Teams (WorkIQ). API path: `mcp_foundry_mcp_project_connection_create`.

## Wiring — Hosted agent (custom code)

```python
# In main.py
mcp_tool = client.get_mcp_tool(
    name="WorkIQTeams",
    project_connection_id="WorkIQTeams2",  # from the connection list
    require_approval=True,                  # Teams writes should require approval
)
agent = Agent(client=client, tools=[..., mcp_tool])
```

## Wiring — Prompt agent (definition-only)

```yaml
# In agent-definition.yaml
tools:
  - type: mcp
    server_label: WorkIQTeams
    project_connection_id: WorkIQTeams2
    require_approval: always
```

MCP scope on the connection: `McpServers.Teams.All`. This is **separate** from Microsoft Graph delegated permissions (`ChannelMessage.Send`, `ChatMessage.Read.All`). If a user reports "agent reads channels but cannot post," they're missing the Graph permission, not the MCP scope.

## Channel publishing — Post-deploy steps (print to user)

After `azd up`, the agent is reachable via its Foundry endpoint but **not** in Teams. To publish:

1. Build a Teams app package referencing the bot Entra app (`bot_app_id` from manifest):
   ```bash
   # Skeleton manifest.json placement
   teamsapp init bot --capability custom-engine-agent --bot-id <bot_app_id>
   teamsapp package
   ```
2. Upload the resulting `.zip` to **Teams Admin Center → Manage apps → Custom Apps**.
3. **Register in Agent 365 / WorkIQ**: Microsoft 365 admin → Copilot → Agents → "Manage agents" → Add → select the Foundry agent and the Teams app. This is the step that makes the agent appear in WorkIQ inventory and audit.
4. (Optional) Assign a sponsor and lifecycle policy in Entra → Agent identities.

Until step 3, Purview audit and Agent 365 inventory will NOT reflect the agent.

## Verification — Post-deploy gate

Run in `/verify-agent` Step 6 when `workiq_teams.enabled: true`:

### V1. Agent appears in Agent 365 inventory
```
GET https://graph.microsoft.com/beta/admin/people/agents
```
Filter for `displayName == "<agent_name>"`. Expect one entry with `runtimeProvider == "Foundry"`.

### V2. Teams app status
Teams Admin Center → Manage apps → search agent name → expect `Status: Allowed`.

### V3. Invocation trace
After a real Teams `@mention`:
```kql
dependencies
| where cloud_RoleName == "${agent_name}"
| where customDimensions.["channel"] == "Teams"
| take 5
```
Empty result after a confirmed Teams interaction → bot Entra app is not routing to the Foundry endpoint. Check the Bot Framework messaging endpoint config.

## Common failure modes

| Symptom | Root cause | Fix |
|---|---|---|
| Agent answers in Foundry portal, not in Teams | App not uploaded / not approved by tenant admin | Step 2 above |
| Agent in Teams, missing from WorkIQ inventory | Step 3 (Agent 365 registration) skipped | Re-run M365 admin flow |
| MCP tool `WorkIQTeams` returns 401 | Connection MCP scope `McpServers.Teams.All` not granted | Foundry portal → connection → Authorize |
| Agent posts but cannot read channel history | Missing Graph delegated permission | Entra app → API permissions → `ChannelMessage.Read.All` |
| Audit shows invocations but no `tool_call` activity in Purview | Purview toggle off (see foundry-purview) | Flip toggle; wait ~30 min |

## Do NOT

- Use the agent's per-agent identity as the bot Entra app — they are different objects.
- Skip Agent 365 registration thinking Teams Admin Center upload is sufficient. WorkIQ inventory is its own surface.
- Hard-code WorkIQ MCP URLs — always go through `project_connection_id`.

## Technical debt / known gaps

- WorkIQ does NOT currently expose a programmatic "is this agent registered?" endpoint that returns AAD-app-bound metadata. The verification path above (Graph beta `admin/people/agents`) is the closest — it may move out of beta.
- Teams app package generation for **legacy** (`identity == null`) agents is still a manual `teamsapp` run; we keep the runbook above pending the upstream upgrade gesture. For new-model agents the [`/publish-teams`](../../prompts/publish-teams.prompt.md) prompt is the orchestrated path.
