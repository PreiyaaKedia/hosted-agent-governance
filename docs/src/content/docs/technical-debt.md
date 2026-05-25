---
title: Technical debt
description: Tracked gaps, trade-offs, and partial implementations — with rationale and close-out plan for each.
---

The on-disk source of truth is [`TECHNICAL_DEBT.md`](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/TECHNICAL_DEBT.md) inside the engineering package. This page is the same content rendered for the docs site.

## Open

| ID | Status | Title | Owning skill |
| --- | --- | --- | --- |
| TD-1 | Open (workaround) | Fabric workspace role assignment is print-only | foundry-fabric |
| TD-3 | Open (preview API) | WorkIQ "is agent registered" check is beta API | foundry-teams-workiq |
| TD-4 | **Partial close (v0.16.0)** | Foundry-native DLP is preview-limited — middleware ships in `audit_only` default; `block` mode requires explicit ack until API GA confirmed | foundry-guardrails (Layer 1.5) |
| TD-5 | Open (low priority) | `apm.yml` has no `repository:` cross-link to skills | (none) |
| TD-6 | Open (CI gap) | No CI gate runs `apm install` against external consumer projects | (CI) |
| TD-7 | Open (UX) | Agent identity propagation timing is not handled gracefully | foundry-identity / `/verify-agent` |
| TD-8 | Open (preview SDK drift) | `azure-ai-projects` SDK surface drift | foundry-evals |
| TD-9 | Open (region staleness) | Cloud red-team region list is hard-coded | foundry-evals |
| TD-13 | Open (deferred by design) | Brownfield code scan is regex-only | foundry-knowledge |
| TD-14 | **Planned (v0.19)** | External persistence for Invocations agents | foundry-deploy (planned) |
| TD-15 | **Planned (post-1.0)** | Microsoft Learn submission | (project) |
| TD-16 | **Planned (when users complain)** | Per-capability requirements snippets + injection helper | foundry-deploy |
| TD-17 | **Phase 1 shipped (v0.18.0)** | Docs site drift from skillpack sources — set-difference drift check; full mirror in Phase 2 | (project / docs) |
| TD-18 | **Open (mitigated, v0.19.0)** | Foundry MCP lacks native `model_deployment_list` — skillpack routes through Azure MCP `mcp_azure_mcp_foundry` for the enumeration call | foundry-deploy / model-selection |
| TD-19 | **Open (alias active, v0.19.0)** | Package renamed `foundry-agent-harness` → `foundry-agent-skillpack` — `aliases:` keeps old name resolving for one release; consumers must update `apm.yml` before v0.20.0 | (project) |

## Closed

| ID | Closed in | Title |
| --- | --- | --- |
| TD-2 | v0.20.0 | Teams publish orchestration — `/publish-teams` + `/configure-rbac post_publish=true` + `publish` schema section |
| TD-10 | v0.20.0 | Network detection deep walkers (NSG / Azure Firewall / SEP) behind `--deep` + BYO-VNet Bicep scaffold + troubleshooter runbook |
| TD-11 | v0.11.0 | `agent-status.json` durable state |
| TD-12 | v0.17.0 | `/audit-drift` prompt |
| TD-23 | v0.22.0 | Inbound firewall coverage for Teams / M365 Copilot → private Foundry agent — `foundry-teams-workiq/inbound-firewall.md` + APIM v2 Bicep + render-apim-policy.sh + probe-inbound-chain.sh + additive `publish.inbound_chain` schema block |

## Pattern

Each TD entry on disk follows this shape:

```markdown
## TD-N — <title>

**What:** <the gap, in one sentence>.

**Why deferred:** <the trade-off>.

**Close-out:** <what would actually close this>.
```

When a TD closes, the **What** stays for history; **Why deferred** is replaced with **Status:** showing what was shipped and where; **Close-out** moves to follow-ons (open as separate TDs when prioritized).

## Why we track these explicitly

Three reasons:

1. **Honest scope.** The skillpack ships preview-adjacent integrations against a moving target. TDs are how we tell consumers "this works for X, not for Y, here's why."
2. **Triggered close-outs.** Many TDs (TD-4, TD-8, TD-9) close when an upstream surface stabilizes. The daily docs-scan workflow (planned) is the trigger. Listing them keeps them surfaceable.
3. **Push-back ammunition.** When someone asks "why doesn't audit-drift auto-fix?" the answer is in the TD list — TD-12 was closed deliberately *without* auto-fix; the rationale is recorded.

## Read next

- [Roadmap](/roadmap/) — sequenced view of what's next.
- [Contributing](/contributing/) — how to propose closing a TD.
