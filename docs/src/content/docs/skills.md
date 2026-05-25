---
title: Skills overview
description: Every skill the skillpack ships, what each one is for, and where to find its source.
---

The skillpack installs **15 engineering skills** + **1 playbook-package skill** = 16 total. Each is a markdown router (`SKILL.md`) plus sub-docs and (where applicable) runnable scripts. Your coding agent loads the routers aggressively and treats sub-docs as on-demand reads.

:::note[Skills are not slash commands]
These **skills** are *knowledge* loaded as context (e.g. `foundry-deploy` ships scaffold templates + capability-manifest schema). They have no inputs and no steps. To **invoke** a workflow, use a **slash command** — e.g. `/plan-agent`, `/configure-rbac`, `/verify-agent`. See [Reference → Prompts](/reference/prompts/) for the 9 slash commands and their parameters, or [Install → Discovering the slash commands](/getting-started/install/#discovering-the-slash-commands) for the per-IDE discovery table.

Naming convention: anything prefixed with `foundry-` is a skill; bare verbs (`plan-agent`, `verify-agent`, …) are prompts.
:::

Skill content is the canonical source — these pages link to it on GitHub for now. (Inline rendering in this site is on the roadmap.)

## Engineering skills

| Skill | Purpose | Sub-docs / scripts |
| --- | --- | --- |
| **foundry-deploy** | Scaffold + deploy hosted agents; SDK pattern; REST API; version lifecycle; external MCP; APIM front-door; capability manifest; **model selection** (single source of truth for `/plan-agent` Step 0b + `/prepare-deploy` Step 2.4); `agent-status.json` schema | [scaffold](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/scaffold.md) · [SDK surface](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/sdk-surface.md) · [external MCP](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/external-mcp.md) · [APIM front-door](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/apim-as-mcp-frontdoor.md) · [capability manifest](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/capabilities-manifest.md) · [model selection](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/model-selection.md) · [agent-status schema](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/agent-status-schema.md) · [LangGraph BYO template](https://github.com/sathik11/foundry-agent-skillpack/tree/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/templates/langgraph-byo) |
| **foundry-identity** | Two-identity model (Project MI + per-agent SP); RBAC matrix; Entra Agent ID; identity discovery scripts | [two identities](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-identity/two-identities.md) · [RBAC matrix](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-identity/rbac-matrix.md) |
| **foundry-roles** | Caller-side role preflight, operator mode (try-first pattern), batch preflight, runbook emit | [role matrix](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-roles/role-matrix.md) · [operator mode](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-roles/operator-mode.md) · [runbook format](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-roles/runbook-format.md) |
| **foundry-knowledge** | Foundry IQ / AI Search / file-search / blob-via-search; decision tree; brownfield code scan; per-source RBAC + network verifiers | [decision tree](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-knowledge/decision-tree.md) · [foundry IQ](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-knowledge/foundry-iq.md) · [AI Search](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-knowledge/ai-search.md) · [file-search](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-knowledge/file-search-tool.md) · [blob via indexer](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-knowledge/blob-via-search.md) · [network compatibility](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-knowledge/network-compatibility.md) |
| **foundry-skills** | Native file-based skills (SkillsProvider) inside the hosted agent | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-skills/SKILL.md) |
| **foundry-guardrails** | Four-layer model — middleware, Purview DLP (unique gap), Content Safety, eval / red-team | [middleware](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-guardrails/middleware.md) · [Purview DLP](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-guardrails/purview-dlp.md) · [Content Safety](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-guardrails/content-safety.md) · [capability gates](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-guardrails/capability-gates.md) |
| **foundry-evals** | Convergent scripts for continuous + scheduled + cloud red-team — audited inside Foundry | [continuous](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-evals/continuous-eval.md) · [scheduled](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-evals/scheduled-eval.md) · [red-team](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-evals/redteam.md) · [evaluator catalog](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-evals/evaluator-catalog.md) |
| **foundry-prod-readiness** | Network classes (managed VNet / BYO VNet / public); cost model; capacity; SLO; production hardening | [networking](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-prod-readiness/networking.md) · [network-troubleshooter](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-prod-readiness/network-troubleshooter.md) |
| **foundry-purview** | Purview governance toggle, audit operations, DSPM | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-purview/SKILL.md) |
| **foundry-fabric** | Fabric Data Agent / direct Delta read (Path A / Path B / hybrid); HARD-BLOCK in network-isolated agents | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-fabric/SKILL.md) |
| **foundry-teams-workiq** | Teams + WorkIQ + Agent 365 integration | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-teams-workiq/SKILL.md) · [publish-flow](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-teams-workiq/publish-flow.md) · [inbound-firewall](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-teams-workiq/inbound-firewall.md) |
| **foundry-multi-agent** | Multi-agent orchestration mechanics — sub-agent invocation, inter-tool data buffer (LLM-bypass for >25 records / >20KB), SSE streaming for >120s pipelines. Walkthrough: [Recipe 06](/recipes/06-multi-agent-orchestration/) | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-multi-agent/SKILL.md) |
| **foundry-patterns** | Common implementation patterns | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-patterns/SKILL.md) |
| **foundry-failure-modes** | Symptom → diagnosis matrix; routes from `/troubleshoot` | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-failure-modes/SKILL.md) |
| **foundry-observability** | OTel spans, App Insights, KQL cookbook, token tracking | [SKILL.md](https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-observability/SKILL.md) |

## Playbook-package skill

| Skill | Purpose |
| --- | --- |
| **foundry-agent-playbook** | Runnable sample agents + 6 end-to-end recipes — reference material; not loaded into agent context for normal use |

## Skill anatomy

Each engineering skill is a folder under `.apm/skills/foundry-<topic>/`:

```
foundry-<topic>/
├── SKILL.md            ← thin router with task table; loaded into context
├── <subtopic-1>.md     ← deep doc, loaded only when referenced
├── <subtopic-2>.md
├── scripts/            ← runnable code (shell, python, KQL, yaml)
└── templates/          ← scaffold templates (foundry-deploy only)
```

Why this split: agents load `SKILL.md` aggressively but treat sub-docs as on-demand reads. Keeping `SKILL.md` thin (≤ 50 lines, mostly a table + cross-refs) lowers the load-time cost. Sub-docs grow without penalty.

## Read next

- [Recipes overview](/recipes/) — end-to-end scenarios that combine multiple skills.
- [Reference: Prompts](/reference/prompts/) — the slash commands skills back.
- [Reference: Scripts](/reference/scripts/) — every runnable script the skills ship.
