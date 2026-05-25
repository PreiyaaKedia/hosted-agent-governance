---
title: Roadmap
description: What's done, what's next, and what's deferred — with the reasoning for each.
---

The skillpack is at **v0.22.0** (May 2026). What's next is sequenced by *value of unblocking* + *real cost of building*. Open follow-ons are tracked in [TECHNICAL_DEBT.md](/technical-debt/) on disk.

## Shipped recently

### v0.22.0 — TD-23 close-out (inbound firewall for private Foundry agents on Teams)

- ✅ **TD-23 — inbound firewall coverage** for the published-bot silent-fail mode (typing indicator → no reply) on `publicNetworkAccess=Disabled` Foundry accounts. Closes the gap where Bot Framework Channel Adapter calls land from the public Microsoft backbone (Teams service tag `52.112.0.0/14`, `52.122.0.0/15`) and cannot reach a private Foundry endpoint.
- ✅ **`foundry-teams-workiq/inbound-firewall.md`** — 8-section runbook: architecture, APIM v2 / YARP / AppGW+APIM decision matrix, paste-ready `<validate-jwt>` policy with `login.botframework.com` OIDC config, prereqs checklist (Key Vault-backed cert because v2 tiers don't support free managed cert, plus Microsoft-suspended-through-2026-06-30 notice), firewall worksheet, 3-probe verification, 6-row failure-mode table, anti-patterns.
- ✅ **`apim-v2-vnet-integrated.bicep`** — paste-ready scaffold for APIM StandardV2 + outbound VNet integration + custom domain (KV cert) + API/operation/policy/product wiring. `@allowed` constrains SKU to `StandardV2` / `PremiumV2` (BasicV2 NOT supported for VNet integration). Subnet delegation `Microsoft.Web/serverFarms`.
- ✅ **`render-apim-policy.sh`** — emits canonical policy XML for non-Bicep deploys; `--inline` substitutes APIM named-value placeholders with concrete values from `agent-status.json`. Byte-identical to the Bicep `<policies>` block (three sources, one truth).
- ✅ **`probe-inbound-chain.sh`** — 3-probe verifier (TLS / missing-auth 401 / synthetic-invalid-JWT 401). `--stamp` writes `publish.inbound_chain` into `agent-status.json` on full pass.
- ✅ **`agent-status.json` schema v1.2** — additive `publish.inbound_chain` block. No `schema_version` bump.
- ✅ **`/publish-teams` Step 0a** — branches on `network.class == "byo_vnet"` OR `publicNetworkAccess == "Disabled"`; prints inbound-firewall handoff banner before preflight.
- ✅ **Cross-skill callouts:** `networking.md` Bot Service asymmetry callout + reply-FQDN allowlist (`smba.trafficmanager.net`, `login.botframework.com`); `network-troubleshooter.md` symptom triage entry; `foundry-failure-modes/SKILL.md` F-20.

### v0.21.0 — Operator mode + discovery scripts

- ✅ **Operator mode (try-first pattern).** Scripts attempt actions directly; runbook only on 403. `operator_mode: true` (default) stamped in `agent-capabilities.yaml` by `/plan-agent` Step 0a. Set `false` for SOC-monitored environments. See `foundry-roles/operator-mode.md`.
- ✅ **Discovery scripts.** `discover-target.sh` (account + project + ACR + model in one call), `select-model.sh` (auto-selects when unambiguous), `safe-azd-init.sh` (guards file clobber + .git reinit).
- ✅ **Batch preflight.** `preflight-roles.sh` checks all roles a prompt needs in one call.
- ✅ **Operator-mode grant scripts.** `try-or-runbook.sh`, `ensure-provider-registration.sh`, `grant-fabric-workspace-role.sh` (partial TD-1 closure), rewritten `grant-purview-dlp-access.sh`.
- ✅ **Prompt rewrites.** `/plan-agent` and `/prepare-deploy` use discovery + batch preflight instead of ad-hoc MCP queries.

### v0.20.0 — TD-2 + TD-10 close-out

- ✅ **TD-2 — `/publish-teams` orchestration prompt** shipped. Detects new vs legacy agent object model, preflights `Microsoft.BotService` + secret scan + BYO-VNet/public-Bot mismatch, patches `agent.yaml` (`BotServiceRbac` + Activity protocol), prints the `azd ai agent publish` CLI (does not execute), captures the project→application identity flip, dispatches `/configure-rbac post_publish=true` for RBAC re-fan, and emits the M365 admin approval runbook.
- ✅ **`/configure-rbac post_publish=true`** mode added — skips Phase 1/2, re-fans Phase 3 grants against the published application identity, writes to `rbac.capability_grants_post_publish`.
- ✅ **`agent-status.json` schema v1.1** — additive `publish` section.
- ✅ **TD-10 — `deep_network` opt-in** on `/prepare-deploy`. Three-layer close-out: deep-walk scripts (NSG, Azure Firewall, SEP) behind `--deep` on `check-source-network.sh`; paste-ready Bicep snippet for BYO VNet + PE + Private DNS; new `network-troubleshooter.md` symptom→fix runbook.

### v0.19.0

- ✅ Package renamed from `foundry-agent-harness` → `foundry-agent-skillpack` (`aliases: [foundry-agent-harness]` ships through v0.22.0 — retirement targeted for v0.23 per TD-19).
- ✅ Astro Starlight documentation site (this site).
- ✅ Azure Static Web Apps deployment workflow.
- ✅ Docs drift checker (`docs/scripts/check-drift.mjs`).

### v0.18.0

- ✅ Rename `foundry-agent-engineering` → `foundry-agent-harness` (superseded in v0.19.0).
- ✅ ROADMAP at repo root + on this site.

## Next minor (v0.23)

| Item | Source | Status |
| --- | --- | --- |
| **TD-19 — retire `foundry-agent-harness` alias** | TECHNICAL_DEBT | Planned (breaking — coordinate with release notes) |
| **TD-14 — External persistence for Invocations agents** (Cosmos / Redis / Storage Tables patterns; new `persistence` block in `agent-capabilities.yaml`) | TECHNICAL_DEBT | Planned |
| **Daily docs-scan workflow** (catches Foundry preview drift; underpins TD-4 / TD-8 / TD-9 close-outs by surfacing API rename + region list changes) | TECHNICAL_DEBT | Planned |
| **`/setup-evals` writes to `agent-status.json` `evals` block** | gap noted in agent-status-schema | Quick follow-on |

## 1.0 candidate

These should land before declaring 1.0:

| Item | Source | Trigger |
| --- | --- | --- |
| **TD-7 — `--wait-for-rbac` flag** (`/verify-agent` polls a known endpoint until success or 20 min timeout) | TECHNICAL_DEBT | When users hit propagation 403s repeatedly |
| **TD-13 — `--ast` flag for `scan_knowledge_refs.py`** (catches aliased imports, conditional imports, framework-specific tool wrappers) | TECHNICAL_DEBT | When first user reports false negative |
| **TD-6 — Consumer-smoke matrix CI job** (validates a fresh consumer project resolves both packages) | TECHNICAL_DEBT | Before public 1.0 |
| **First-class APIM `kind` in `verify-source-rbac.sh`** | Recipe 05 callout | Cleans up Recipe 05 |

## Post-1.0

| Item | Source | Notes |
| --- | --- | --- |
| **TD-15 — Microsoft Learn submission** | Roadmap doc | Months-long content + IP review; aim once adoption justifies |
| **`register-custom-agent` flow** (true outside-Foundry agents — separate `foundry-control-plane` skill) | Brainstorm | Distinct from Invocations protocol; agents running in your own AKS / EKS / on-prem |
| **TD-4 promotion — Foundry-DLP `block` mode out of preview-warning** | TECHNICAL_DEBT | When Purview classification API + token surface confirmed GA |
| **TD-1 Fabric workspace API automation** (replace print-only with API call when Fabric-aud token can be obtained cleanly) | TECHNICAL_DEBT | When Fabric workspace add is exposed via Graph or similar |
| **Legacy-agent upgrade-gesture branch retirement in `/publish-teams`** | TD-2 verification track | When MS Learn legacy → new-model upgrade gesture GAs |

## Backlog

Ideas tracked but not committed:

- Multi-language brownfield scanner (TypeScript / C# in addition to Python).
- VS Code Foundry extension surface that renders the audit-drift report inline.
- Per-skill testing sub-docs (today recipes are the only end-to-end test path).
- Foundry-skills sample sub-doc (today the SKILL.md is the only doc — could grow).

## Explicit non-goals

Things we have deliberately decided not to do:

- **Auto-fix in `/audit-drift`**. Drift detection and remediation are different code paths. `/audit-drift` reads; `/configure-rbac` + `/verify-agent` write. Auto-fix risks silently re-granting roles that were deliberately revoked.
- **Data-plane smoke retrieves in `/audit-drift`**. That's `/verify-agent`'s job — audit shouldn't trigger live agent invocations on a weekly schedule.
- **Hosting our own MCP server**. Boundary stays at "knowledge package + scripts." If we ever ship one, separate repo.
- **`agent-graph.json` as a separate artifact**. Subsumed by `agent-status.json` (one artifact, multiple readers).
- **Executing `azd ai agent publish` from `/publish-teams`**. Mutating publish stays operator-visible (matches the `azd up` boundary). The prompt prints the CLI; the human runs it.
- **Executing role assignments from `refan-rbac-post-publish.sh`**. Script emits the exact `/configure-rbac post_publish=true` invocation; grants stay in the audited prompt path.

## Read next

- [Technical debt](/technical-debt/) — the on-disk TD-N tracking that this roadmap is derived from.
- [Contributing](/contributing/) — how to propose roadmap items.
