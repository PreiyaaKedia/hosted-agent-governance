---
name: foundry-failure-modes
description: 25 verified failure modes with symptom-to-fix lookup for Foundry hosted agents
---

# Foundry Failure Modes

## Quick Triage

| Symptom | Check | Fix |
|---------|-------|-----|
| 400 on version create | Env var prefix or missing metadata | Remove `FOUNDRY_*`/`AGENT_*` prefixes |
| Version `failed` | ImageError → AcrPull; other → docker test | Grant AcrPull to Project MI, POST new version |
| 403 at runtime | Instance MI roles at account scope | Grant `Azure AI User` at **account** scope |
| Model 400 on sub-agent | Model mismatch | `SUBAGENT_MODELS` mapping per agent |
| Sync timeout | Pipeline >120s | Use `"stream": true` |
| Fabric returns 0 rows | NL2SQL non-determinism | Implement deterministic fallback |
| Tool name rejected | Dots in MCP name | Wrap in `@tool` with clean name |
| Stream cuts silently | LLM serialization bottleneck | Inter-tool data buffer |
| Sub-agent fails randomly | Transient platform errors | Retry 5x with exponential backoff |
| Eval shows "Failed" | No-data (not broken) | Generate traffic, next run picks it up |
| Teams `@mention` types but never replies (private Foundry) | Inbound chain missing OR reply FQDNs blocked | Stand up reverse proxy per [inbound-firewall.md](../foundry-teams-workiq/inbound-firewall.md); confirm `smba.trafficmanager.net` + `login.botframework.com` allow-listed |

## Deployment Failures

- **F-01 `400 EnvVarReserved`**: Rename from `FOUNDRY_*` to your own prefix (e.g., `MYPROJECT_*`)
- **F-03 ImageError**: Grant `AcrPull` to Project MI on ACR. POST new version (failed ones don't retry)
- **F-04 PrincipalTypeNotSupported**: Use `instance_identity.principal_id`, NOT `blueprint.principal_id`
- **F-05 Health timeout**: Test locally with `docker run` — expect port 8088 within 25s

## Runtime Failures

- **F-06 Container boots then 403**: `Azure AI User` missing at **account** scope (not just project)
- **F-07 Model 401/403**: `Cognitive Services OpenAI User` missing at account scope
- **F-08 Model mismatch 400**: `model` in request must exactly match sub-agent's configured model
- **F-09 120s sync timeout**: Use SSE streaming for multi-agent pipelines

## Data Access Failures

- **F-10 NL2SQL 0 rows**: Non-deterministic. Always have fallback.
- **F-11 Soft errors**: HTTP 200 but text says "unable to retrieve". String-match to detect.
- **F-12 MCP dots**: Toolbox namespaces as `server.tool` → 400. Wrap in `@tool`.
- **F-13 Toolbox works but direct read 403s**: Different identities (Project MI vs per-agent)

## SDK Failures

- **F-14 ImportError `_telemetry`**: Use `agent-framework-foundry-hosting==1.0.0a260429` or later
- **F-15 TextContent import**: Use `Message("assistant", [string])` instead
- **F-16 "usage not supported"**: Informational only — safe to ignore

## Multi-Agent Failures

- **F-17 Stream closes silently**: LLM serializing 20KB+ as tool argument. Use data buffer.
- **F-18 Intermittent 408/refused**: Retry 5x with 2s/4s/8s/8s backoff. All transient.
- **F-19 50KB+ server_error**: Truncate to 30 records before passing downstream.

## Publish / Channel Failures

- **F-20 Teams `@mention` succeeds, no reply** (silent publish, private Foundry):
  - **Symptom**: Bot installed in Teams, `@mention` shows typing indicator, reply never lands. No error in App Insights, no entry in Foundry trace, no 4xx anywhere obvious.
  - **Root cause (inbound leg)**: Foundry account has `publicNetworkAccess=Disabled` (or BYO VNet) and the Bot Service messaging endpoint points directly at the Foundry FQDN. Bot Framework Channel Adapter calls land on the public Microsoft backbone from the Teams service tag — they cannot reach a private endpoint. Foundry never sees the request.
  - **Root cause (outbound leg)**: Inbound chain is fine, agent processes the activity, but its egress firewall blocks `smba.trafficmanager.net` (the reply queue), so the reply is silently dropped.
  - **Fix**: Front the private agent with a customer-owned reverse proxy that validates the Bot Framework JWT and forwards to the Foundry PE. Paste-ready APIM v2 + VNet integration scaffold + decision matrix in [foundry-teams-workiq/inbound-firewall.md](../foundry-teams-workiq/inbound-firewall.md). Verify with `probe-inbound-chain.sh <agent_path> <custom_domain>` (3 probes; non-zero exit on any deviation).
  - **Allowlist `smba.trafficmanager.net` + `login.botframework.com`** on the agent's egress firewall before declaring health — see [foundry-prod-readiness/networking.md § Firewall allowlist](../foundry-prod-readiness/networking.md#firewall-allowlist-byo-vnet--azure-firewall).
