# Technical Debt

Tracked gaps and trade-offs in the foundry-agent-skillpack APM package. Each entry: what / why deferred / what would close it.

> **Rename history:**
> - **v0.18.0 (May 2026):** package renamed from `foundry-agent-engineering` → `foundry-agent-harness`.
> - **v0.19.0 (May 2026):** package renamed from `foundry-agent-harness` → `foundry-agent-skillpack`. `aliases: [foundry-agent-harness]` ships from v0.19.x through v0.22.0; slated to drop in v0.23. See [TD-19](#td-19--package-rename-foundry-agent-harness--foundry-agent-skillpack).
>
> Prior TD entries reference older names in commit history; the package contents are continuous. See [`ROADMAP.md`](../ROADMAP.md) for sequencing.

## TD-1 — Fabric workspace role assignment is print-only

**What:** `/configure-rbac` prints the Fabric portal/REST steps to add the per-agent identity as a workspace `Member` instead of executing the call.

**Why deferred:** The Fabric `POST /workspaces/{id}/roleAssignments` API requires a Fabric-aud delegated token (`api.fabric.microsoft.com/.default`), not an `https://management.azure.com/.default` token from `az`. Acquiring it cleanly inside an APM prompt requires either:
- A Service Principal that already has `Fabric Administrator` (chicken-and-egg), or
- An interactive `az login --scope api.fabric.microsoft.com/.default` flow that disrupts the prompt flow.

**Close-out:** Detect if the user is a Fabric admin (Graph: `directoryRoles` for `Fabric Administrator`); if so, prompt for explicit `az login --scope` and call the API. Otherwise stay print-only.

## ~~TD-2 — Teams publish orchestration~~ **(CLOSED in v0.20.0)**

**Status (v0.20.0):** Closed. The new-model identity-flip gap is now orchestrated by [`/publish-teams`](.apm/prompts/publish-teams.prompt.md) + [`/configure-rbac post_publish=true`](.apm/prompts/configure-rbac.prompt.md), backed by:

- [foundry-teams-workiq/publish-flow.md](.apm/skills/foundry-teams-workiq/publish-flow.md) — full flow documentation (preflight, agent.yaml patch, publish CLI handoff, identity-flip capture, RBAC re-fan, M365 admin runbook).
- [foundry-teams-workiq/scripts/preflight-publish.sh](.apm/skills/foundry-teams-workiq/scripts/preflight-publish.sh) — hard-gates `BotService` RP registration, `BYO_VNET_PUBLIC_BOT_MISMATCH`, continuous-eval rule presence, Purview enablement, and publish-metadata secret scan.
- [foundry-teams-workiq/scripts/refan-rbac-post-publish.sh](.apm/skills/foundry-teams-workiq/scripts/refan-rbac-post-publish.sh) — resolves the application identity and emits the exact `/configure-rbac post_publish=true` invocation.
- New `publish` section in [agent-status-schema.md](.apm/skills/foundry-deploy/agent-status-schema.md#publish--written-by-publish-teams-and-configure-rbac---post-publish-td-2) (schema v1.1, additive). `agent_status.py` `ALLOWED_SECTIONS` extended.
- `/configure-rbac` `post_publish` input added: skips Phase 1/2, re-fans Phase 3 grants against `publish.application_identity_principal_id`, writes to `rbac.capability_grants_post_publish` (preserves pre-publish state for audit), stamps `publish.rbac_refanned_at`.

**Legacy branch:** Agents with `identity == null` still print the existing `teamsapp` runbook from [foundry-teams-workiq/SKILL.md § Channel publishing](.apm/skills/foundry-teams-workiq/SKILL.md#channel-publishing--post-deploy-steps-print-to-user). When the upstream upgrade gesture for legacy → new agents GAs (currently "Coming soon" per MS Learn), this branch drops — tracked under quarterly verification.

**Original gap (largely obsoleted upstream):** `foundry-teams-workiq` SKILL printed the `teamsapp` CLI commands to build a Teams app .zip but did not execute them.

**Why obsoleted:** Foundry portal vNext (Early Access Preview) ships a **Direct Publish to Teams / M365 Copilot** button that auto-creates the Azure Bot Service resource and dispatches the M365 admin approval workflow. For agents on the new agent object model (`agent.identity != null`), the manifest-packaging chore that TD-2 was scoped to handle is no longer the customer-facing problem. ([MS Learn: Publish agents to Microsoft 365 Copilot and Microsoft Teams](https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot))

**New gap declared (the surface widened, not narrowed):** Publishing flips the agent's runtime identity from the project identity to a new application identity. MS Learn (verbatim): *"Plan for identity changes when you publish. Tool calls authenticated by agent identity use the application identity after publishing, not the project identity."* ([Publish your agent as an Agent Application](https://learn.microsoft.com/azure/foundry/agents/how-to/agent-applications)) Every RBAC grant `/configure-rbac` made pre-publish breaks unless re-fanned. This is the new TD-2-shaped problem.

**Close-out (new):** Ship a `/publish-teams` prompt that handles the broader publish event:
1. Detect new vs legacy agent object model (`agent.identity` null check).
2. Legacy path: keep existing `teamsapp` runbook until the upstream upgrade gesture ships ("Coming soon" per MS Learn).
3. New path:
   - Preflight `Microsoft.BotService` provider registration in the subscription.
   - Configure Activity protocol + BotService / BotServiceRbac authorization scheme on `agent.yaml` (required for M365/Teams publish per MS Learn).
   - Detect BYO-VNet ↔ public Bot Service mismatch.
   - Scan publish metadata (display name, descriptions, URLs) for accidental secrets — MS Learn explicitly warns.
   - Gate publish on `/setup-evals` pass + `/setup-purview` middleware presence.
   - On post-publish: `/configure-rbac --post-publish` to re-fan the RBAC matrix from project identity to the new application identity.
   - Capture publish event as a delta in `agent-status.json` for `/audit-drift`.
   - Emit M365 admin approval runbook for "People in your organization" scope (admin center URL + paste-ready Teams message for the admin).

**Verification (track quarterly):** Re-check MS Learn for the legacy-agent upgrade gesture GA — once shipped, drop the legacy-path branch.

**Deck revisit required after merge:** Update Approach A Slide 4 — move Teams items from the ⚠ hand-off list into the ✓ orchestration list with implementation evidence. Update Approach B Slide 5 Card 2 to reference the shipped `/publish-teams` prompt (not "roadmap"). Update `00-objective-and-problem.md` open-in-flight to mark `/publish-teams` shipped.

## TD-3 — WorkIQ "is agent registered" check is beta API

**What:** `/verify-agent` uses `GET https://graph.microsoft.com/beta/admin/people/agents` to confirm Agent 365 inventory.

**Why:** No GA endpoint exists yet for programmatic Agent 365 inventory.

**Close-out:** Replace with GA endpoint when available (track Graph release notes).

## TD-4 — Foundry-native DLP is preview-limited (PARTIAL CLOSE in v0.16.0)

**What:** `purview.dlp.enabled: true` in the capabilities manifest prints a hard warning and stops; full SIT scanning + label enforcement requires Purview SDK middleware which is not part of this package.

**Status (v0.16.0):** Partially closed by shipping the **Layer 1.5 Purview DLP middleware** under [foundry-guardrails/purview-dlp.md](.apm/skills/foundry-guardrails/purview-dlp.md) + [scripts/purview_dlp_middleware.py](.apm/skills/foundry-guardrails/scripts/purview_dlp_middleware.py). The middleware:
- Calls Purview classification API per turn (input + response, optionally tool results).
- Acts on the verdict per `enforcement_mode`: `audit_only` | `warn` | `block`.
- Defaults to `audit_only` (always safe, fail-open on classifier errors).
- Requires explicit `AGREE_PURVIEW_DLP_PREVIEW=1` env var to start in `block` mode (constructor refuses without it).
- Emits structured OTel spans (`guardrail.purview_dlp.*`) for KQL + dashboards.

**Why not full close:** Three preview-grade gaps remain that require Purview-side GA:
1. **Token surface uncertainty.** The Purview classification API may require a Compliance-Admin-tier token for some tenants. Middleware uses `DefaultAzureCredential`; if your tenant requires elevated rights, you accept the risk of the secret in agent env vars.
2. **Label propagation through OBO.** Sensitivity labels in source documents only appear in classification responses when the source surfaces them via OBO (M365 path). For Foundry-hosted with `acl_passthrough: false`, only labels embedded in the prompt/response text are detected.
3. **API shape stability.** The `/classify` endpoint shape is preview-adjacent. If the shape changes, the middleware's `_classify` method needs swapping (rest of the middleware is shape-agnostic).

**Close-out:** Re-validate against Purview GA docs (daily docs scan flags surface changes); promote to full close when (1)–(3) above resolve.

## TD-5 — `apm.yml` has no `repository:` cross-link to skills

**What:** Skills do not declare individual `repository:` URLs; they share the package's.

**Why:** APM does not require it.

**Close-out:** Add `repository:` to each skill front-matter when the package crosses 1.0.

## TD-6 — No CI gate runs `apm install` against external consumer projects

**What:** `.github/workflows/apm-install-test.yml` validates the package resolves but does not validate that a typical consumer project can `apm install` + `apm compile -t copilot` cleanly.

**Close-out:** Add a `consumer-smoke` matrix job that creates a fresh repo, declares this package as a dep, and runs `apm install` + `apm audit` + `apm compile`.

## TD-7 — Agent identity propagation timing is not handled gracefully

**What:** Several gates note "RBAC propagation: 5–15 minutes" but `/verify-agent` runs immediately after `/configure-rbac`, often hitting 403.

**Close-out:** Add `--wait-for-rbac` flag that polls a known endpoint until success or 20 min timeout, with backoff.

## TD-8 — `azure-ai-projects` SDK surface drift

**What:** The `foundry-evals/scripts/ensure_*.py` wrappers call `evaluation_rules.create_or_update`, `schedules.create_or_update`, `red_teams.create`, and several model classes (`EvaluationRule`, `ContinuousEvaluationRuleAction`, `EvaluationRuleFilter`, `ProjectsSchedule`, `RecurrenceTrigger`, `EvaluationScheduleTask`, `RedTeam`, `AzureAIAgentTarget`) that are still moving in the preview SDK. Each script defensively falls back to the older `.create` surface when `.create_or_update` is missing, but new method renames will break us.

**Why deferred:** Foundry observability + red-team SDK is in active preview. Wrapping it now is the right call for audit-trail-in-Foundry, but we accept maintenance.

**Close-out:** A daily docs scan (Microsoft Learn MCP + Context7) flags the canonical method names; CI re-runs the wrappers against `azure-ai-projects` `latest` and pinned. Bump the pin window in `_common.py` + README in lockstep.

## TD-9 — Cloud red-team region list is hard-coded

**What:** [foundry-evals/scripts/ensure_redteam.py](.apm/skills/foundry-evals/scripts/ensure_redteam.py) hard-codes `SUPPORTED_REGIONS = {"eastus2", "francecentral", "swedencentral", "switzerlandwest", "northcentralus"}` as of 2026-05-14.

**Why deferred:** No public API exposes the supported region set programmatically.

**Close-out:** Daily docs scan against [Run AI Red Teaming Agent in the cloud](https://learn.microsoft.com/azure/foundry/how-to/develop/run-ai-red-teaming-cloud) updates the constant via PR. Until that lands, the script asks the human to verify.

## ~~TD-10 — Network detection scripts don't walk NSGs / Azure Firewall / SEPs~~ **(CLOSED in v0.20.0)**

**Status (v0.20.0):** Closed via the three-layer opt-in path documented in the close-out spec below.

**Shipped:**
- **Layer 1 — Deep walkers** (opt-in via `--deep`):
  - [scripts/network/deep-walk-nsg.sh](.apm/skills/foundry-prod-readiness/scripts/network/deep-walk-nsg.sh) — declared NSG rules + best-effort effective rules via `az network nic list-effective-network-security-rules`.
  - [scripts/network/deep-walk-firewall.sh](.apm/skills/foundry-prod-readiness/scripts/network/deep-walk-firewall.sh) — both classic application-rule collections and policy-based `ruleCollectionGroups`; FQDN-tag hints emitted.
  - [scripts/network/check-service-endpoint-policy.sh](.apm/skills/foundry-prod-readiness/scripts/network/check-service-endpoint-policy.sh) — flags SEP blocks on Foundry / Storage / AI Search service tags.
  - [scripts/network/check-source-network.sh](.apm/skills/foundry-prod-readiness/scripts/network/check-source-network.sh) extended with `--deep <agent_subnet_id> [<firewall_id>] [<fqdn>...]` to cascade the three walkers.
  - [`/prepare-deploy`](.apm/prompts/prepare-deploy.prompt.md) extended with `deep_network` input that wires `--deep` into the per-source loop.
- **Layer 2 — BYO VNet hand-off:** [scripts/network/templates/byo-vnet-with-pe.bicep](.apm/skills/foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep) — paste-ready VNet + delegated subnet + PE + Private DNS scaffold for `azd up`. The scripts emit a pointer to this file when `publicNetworkAccess=Disabled` and no PE is present.
- **Layer 3 — Troubleshooter runbook:** [foundry-prod-readiness/network-troubleshooter.md](.apm/skills/foundry-prod-readiness/network-troubleshooter.md) — symptom-triage table, full deep-walk command examples, DNS-from-Bastion fallback, and re-baseline command for `agent-status.json`.
- [networking.md](.apm/skills/foundry-prod-readiness/networking.md) "What the detection scripts deliberately leave to humans" section refreshed — Layer 1 now covered; remaining out-of-scope items (provisioning, cross-tenant peering, agent-side DNS) explicitly listed.

**Original gap:**

**What:** [foundry-prod-readiness/scripts/network/check-source-network.sh](.apm/skills/foundry-prod-readiness/scripts/network/check-source-network.sh) checks `publicNetworkAccess`, `networkAcls.defaultAction`, IP / VNet rule counts, and PE count — then prints "if NSG/Firewall is in place, verify outbound 443 manually".

**Why deferred:** Walking NSG rule chains, Azure Firewall application rules, and Service Endpoint Policies is high-maintenance and tenant-shape-specific. Most silent failures are caught by the four checks above + private DNS linkage; the residual is best handled by a human eyeball.

**Close-out (PR-ready spec, three layers):**

1. **Opt-in `--deep-network` flag** on `/prepare-deploy` (default off; slow path 60–120 s typical):
   - New script `scripts/network/deep-walk-nsg.sh <subnet-id>` — walks NSG rules on the agent's subnet *and* the source workload's subnet via `az network nic list-effective-network-security-rules`; checks outbound 443 against the canonical Foundry / source FQDNs declared in `agent-capabilities.yaml`.
   - New script `scripts/network/deep-walk-firewall.sh <firewall-id>` — enumerates Azure Firewall application rules via `az network firewall application-rule list` if a Firewall is detected in the route path.
   - New script `scripts/network/check-service-endpoint-policy.sh <subnet-id>` — `az network vnet subnet show --query serviceEndpointPolicies` to flag SEP blocks on Foundry / Storage / AI Search service tags.
   - Wire the three into `check-source-network.sh` behind a `--deep` flag so callers can keep the fast path by default.

2. **Known-good Bicep snippet emission** (closes the "detect → recommend → hand off" gap):
   - New file `scripts/network/templates/byo-vnet-with-pe.bicep` — minimal VNet + Private Endpoint + Private DNS zone in a known-good configuration for Foundry.
   - `check-source-network.sh` prints "drop this snippet into `./infra/main.bicep` and re-run `azd up`" when detection finds BYO VNet without a working PE. We don't run `az network create`; we hand off a paste-ready artifact.

3. **`network-troubleshooter.md` runbook** (converts unknown failures → known failure modes):
   - New doc `foundry-prod-readiness/network-troubleshooter.md` — step-by-step: "agent returns 503" → identify network class via `check-foundry-network-mode.sh` → re-run `check-source-network.sh --deep` → manual `curl` / `nslookup` from a Bastion host → link to the right Azure portal blade.
   - Cross-link from `foundry-prod-readiness/SKILL.md` failure-mode index and from the runbook-emit script.

**Trigger:** Multiple users hit silent NSG-block failures (was: "only if"); now elevated because Approach A Slide 4 of the exec deck claims this work; we should ship it on the same release that the deck is presented.

**Deck revisit required after merge:** Update Approach A Slide 4 ⚠ hand-off list — move "Network: VNet / PE / NSG provision" out of the ⚠ column for the `--deep` path; keep the runbook hand-off framing for the provision step. Update `00-objective-and-problem.md` validated facts to drop "network scripts are read-only detection only" once the `--deep` flag ships (note still applies to provisioning).

## TD-11 — ~~`agent-status.json` durable state is not yet implemented~~ (CLOSED in v0.11.0)

**What:** Per-agent durable record of identities, RBAC outcomes, network detection results, eval rule IDs, verify outcomes, and capability-hash baselines for drift detection.

**Status:** Closed in v0.11.0. Schema in [foundry-deploy/agent-status-schema.md](.apm/skills/foundry-deploy/agent-status-schema.md), helper in [foundry-deploy/scripts/agent_status.py](.apm/skills/foundry-deploy/scripts/agent_status.py). Three readers wired:
- `/prepare-deploy` — init + stamp `preflight` + `network` + baseline `drift.capability_hash_at_preflight`
- `/configure-rbac` — stamp `identities` + `rbac.phases_completed` + `rbac.capability_grants` + `rbac.pending` + re-baseline `drift.capability_hash_at_rbac`
- `/verify-agent` — drift check at Step −1, stamp `deploy` + `verify`

**Follow-ups (open as separate TDs when prioritized):**
- `/audit-drift` prompt (TD-12, planned) — 4th reader, surfaces declared-vs-observed deltas without mutating.
- Helper-side schema validation tightening (currently loose: section names enforced, fields free) when churn warrants — bump `schema_version` and ship a migration.

## TD-12 — ~~`/audit-drift` prompt~~ (CLOSED in v0.17.0)

**What:** Read-only declared-vs-observed reconciler. Walks `agent-capabilities.yaml` + the live world (Azure RBAC, Foundry connections, eval rules, Purview toggle, network class) and emits a markdown delta report. Never mutates.

**Status:** Closed in v0.17.0. Implementation: [.apm/prompts/audit-drift.prompt.md](.apm/prompts/audit-drift.prompt.md) (single prompt, no new scripts). Forward + reverse drift detection. Stamps `agent-status.json` `verify` block with `last_audit_at`, `audit_summary`, `audit_report_path` (additive — doesn't replace `/verify-agent`'s fields).

**Operational integration:**
- Documented in [recipes/02-brownfield-onboarding.md](../foundry-agent-playbook/.apm/skills/foundry-agent-playbook/recipes/02-brownfield-onboarding.md) Step 9 as the recommended weekly maintenance task.
- Designed for non-blocking CI scheduling — not a PR gate. (`/verify-agent` is the PR gate.)

## TD-13 — Brownfield code scan is regex-only (acceptable trade-off, tracked for visibility)

**What:** [foundry-knowledge/scripts/scan_knowledge_refs.py](.apm/skills/foundry-knowledge/scripts/scan_knowledge_refs.py) uses line-level regex against Python source files — not AST, not framework introspection. Misses: same-line aliased imports (`from azure.search.documents import SearchClient as SC`), conditional imports inside try/except, framework-specific tool registration patterns we don't have a regex for.

**Why this trade-off:** Per the agreed design, code scan is a *signal* not a source of truth — the scan always asks the user to confirm/edit, never silently classifies. AST-based scanning is a 5x complexity jump for marginal recall gain.

**Close-out:** Add an optional `--ast` flag using `ast` + framework-specific visitors only when (a) we hit multiple users with false negatives, or (b) we add support for a framework whose patterns are too dynamic for regex (e.g., DSPy).

## TD-14 — External persistence for Invocations agents (PLANNED — next-version roadmap)

**What:** Invocations-protocol hosted agents (webhook receivers, AG-UI streamers, batch processors) get NO platform-managed conversation history. The platform persists `agent_session_id` sandbox state for up to 30 days with a 15-minute idle timeout, but anything beyond that — cross-session user preferences, durable workflow state, multi-month chat histories — is the agent's responsibility.

**Why this matters now (and not for Responses):** Responses-protocol agents get `previous_response_id` / `conversation` autobind for free; the platform stores message history server-side. Invocations agents don't — because the payload shape is arbitrary, the platform can't infer what "history" means.

**Why deferred:** Three patterns that need separate sub-docs and per-pattern grant scripts (Cosmos DB, Redis, Storage Tables). Each requires capability-manifest schema extension (`persistence` block) + Phase A preflight + Phase B grants + Phase C verify. Full close is 5–7 files; not in scope for v0.16.0.

**Close-out plan (next-version roadmap):**
1. New sub-doc `foundry-deploy/external-persistence.md` covering decision matrix (do you actually need this?) + Cosmos / Redis / Storage Tables patterns + anti-pattern of treating `$HOME` as durable.
2. Schema extension: `persistence` block in `agent-capabilities.yaml` (optional; only declared by Invocations agents).
3. Per-store Phase B grant scripts under `foundry-deploy/scripts/persistence/` (or a new `foundry-state` skill if patterns grow).
4. `/configure-rbac` dispatch: Phase B grant per declared store (Cosmos data-plane role, Storage Blob Data Contributor, etc.).
5. `/verify-agent` Phase C: read/write a sentinel item end-to-end.

**Note:** This is distinct from the (also unscoped) `register-custom-agent` flow, which is for agents *running entirely outside Foundry* with Foundry just providing monitoring/eval. That's its own potential future skill (`foundry-control-plane` or similar).

## TD-15 — Microsoft Learn submission (PLANNED — post-1.0)

**What:** Submit the skillpack's content to Microsoft Learn (`learn.microsoft.com/azure/foundry/...`) for inclusion in the official Foundry hosted-agent documentation surface. Today this content is community-published via Astro Starlight + Azure Static Web Apps; Microsoft Learn would put it in the same place dev teams already look for Azure docs.

**Why deferred:** Microsoft Learn submission is a months-long process: content review, IP review, branding review, Microsoft assuming ownership of the URL and editorial cadence. It's the right destination eventually but not the right destination *yet* — the skillpack is iterating quickly against a preview-adjacent Foundry surface, and the Learn submission process trails active development by 6–12 months.

**Close-out plan (post-1.0):**
1. Wait until adoption justifies the submission cost (e.g., ≥ 100 stars, ≥ 5 distinct organizations using in production).
2. Identify a Microsoft sponsor for the submission (Foundry product team or Azure Apps + AI DX).
3. Author submission package: content, IP attestation, brand alignment.
4. Negotiate which content lives where (some content stays on the docs site as community extension; some moves to Learn as canonical).
5. Set up redirects from `foundry-agent-skillpack.example.com` to the Learn URLs for migrated pages.

**Until then:** the Astro Starlight site at `docs/` is the canonical render.

## TD-16 — Per-capability requirements snippets (PLANNED — when users complain)

**What:** Today, container-side Python dependencies needed per declared capability live in a single table in [foundry-deploy/runtime-dependencies.md](.apm/skills/foundry-deploy/runtime-dependencies.md). The user must read it, cross-reference their `agent-capabilities.yaml`, and manually append the right lines to their `requirements.txt`.

**Why deferred:** v0.18 ships with the single-page table because (a) it's enough for the current user count and (b) any automation that mutates user code is a stronger boundary than the skillpack has crossed. The cheap fix wins until real users complain.

**Close-out plan (when triggered):**
1. Per-capability `requirements-snippet.txt` files under each skill's `scripts/` folder (e.g., `foundry-guardrails/scripts/requirements-snippet.txt`, `foundry-knowledge/scripts/requirements-snippet.txt`).
2. New helper `foundry-deploy/scripts/inject-requirements.sh` — given an `agent-capabilities.yaml`, **prints** the lines to append (never mutates the user's file). Pattern: same posture as `runbook-emit.sh` — emit a paste-ready block.
3. `/prepare-deploy` Track H3 gate reports a delta: declared capabilities vs `requirements.txt` content; suggests the helper.
4. Document in `runtime-dependencies.md` § "How to update your existing requirements.txt".

**Triggers to start work:**
- Multiple users miss a runtime dep at deploy time (e.g., `ModuleNotFoundError` after `azd up`).
- A new capability is added that has non-obvious deps (TD-14 external persistence is a likely trigger).

## TD-17 — Docs site drift from skillpack sources (PHASE 1 SHIPPED in v0.18.0; Phase 2 post-1.0)

**What:** The docs site (`docs/src/content/docs/`) is a **curated subset** of the skillpack's skill content, not a mirror. Today:
- **Recipes** are mirrored automatically (`docs/scripts/mirror-recipes.mjs` runs on every dev/build).
- **Skills, prompts, TECHNICAL_DEBT, concept pages** are hand-curated and drift from the underlying sources.

**Why this matters:** small skill-level changes get made without updating the docs site, so the published documentation lags the actual skillpack behavior over time.

**Why a full mirror isn't the right answer (yet):**
- Skills are written for an LLM's context window (terse routers + sub-docs). Verbatim rendering on a docs site gives wall-of-text pages.
- Curated concept pages (`what-is-this.md`, `lifecycle.md`, etc.) are higher-quality than a raw skill mirror would produce.
- Heterogeneous skill shapes mean the mirror script would need per-skill rules.

**Status:**

*Phase 1 — Drift check script (SHIPPED in v0.18.0).*

Implementation:
- [`docs/scripts/check-drift.mjs`](../docs/scripts/check-drift.mjs) — set-difference check across three surfaces:
  - Skills directory ↔ `docs/src/content/docs/skills.md` table.
  - Prompts directory ↔ `docs/src/content/docs/reference/prompts.md`.
  - `TECHNICAL_DEBT.md` `## TD-N` entries ↔ `docs/src/content/docs/technical-debt.md` table.
- CI integration in `.github/workflows/docs.yml`: a `Check for docs ↔ skillpack drift` step that runs before the build, emits the report to `$GITHUB_STEP_SUMMARY`, and is non-blocking (`continue-on-error: true`). PR reviewers see the report on the workflow run page.
- Output format: markdown report with ✅ / ⚠ per surface, plus a summary count.
- Exit code: always 0. The script is a nag, not a gate. By design.

What it deliberately doesn't do:
- No content-equality check. Paraphrased prose between source and docs is the whole point of a curated docs site; flagging every difference would be noise.
- No auto-fix. Drift is a human-review concern.
- No block-on-drift. PR authors get a heads-up; reviewer + author decide whether to update.

*Phase 2 — Mirror script for skills (post-1.0).*
1. `docs/scripts/mirror-skills.mjs` that mirrors **SKILL.md routers only** (not sub-docs) into `docs/src/content/docs/skills/<name>.md`.
2. Sub-docs continue to live in the skillpack; the docs-site skill page links to them on GitHub.
3. Curated concept pages stay hand-written — they're not mechanical mirrors.

**Operational note:** when you add or rename anything in `foundry-agent-skillpack/.apm/skills/`, the drift check will flag the gap in the next PR. Update the matching docs page (`skills.md`, `reference/prompts.md`, or `technical-debt.md`) in the same PR to close it.

## TD-18 — Foundry MCP lacks native `model_deployment_list` (OPEN — mitigated)

**What:** The Foundry MCP server exposes per-name `mcp_foundry_mcp_model_deployment_get` (returns 404 if the deployment is absent) but no list-by-account endpoint. `/plan-agent` Step 0b and `/prepare-deploy` Step 2.4 need to enumerate existing deployments in `target.foundry_account` to render a picklist.

**Status (mitigated, v0.19.0):** The skillpack routes through `mcp_azure_mcp_foundry` (action: `deployments.list`) for the enumeration call, then continues to use `mcp_foundry_mcp_model_deployment_get` for per-name validation and `mcp_foundry_mcp_model_deploy` for create. This split is documented in [foundry-deploy/model-selection.md](.apm/skills/foundry-deploy/model-selection.md) Step 1, with the rationale explicitly noted so future maintainers don't try to "consolidate" by hand-rolling REST calls.

**Why not full close:** Going through Azure MCP introduces a second tool dependency for what should be a single-MCP capability. It's a maintenance footnote, not a user-facing problem — both tools are stable and shipped.

**Close-out:** When Foundry MCP ships `mcp_foundry_mcp_model_deployment_list` (or equivalent), swap the call site in `model-selection.md` Step 1 and remove the cross-reference. One-file change. Track Foundry MCP release notes via the daily docs scan.

## TD-19 — Package rename `foundry-agent-harness` → `foundry-agent-skillpack` (OPEN — alias active)

**What:** v0.19.0 renames the package directory and all references from `foundry-agent-harness` to `foundry-agent-skillpack` (the second rename in this package's history; v0.18.0 was `engineering` → `harness`). To avoid breaking external consumers' `apm.yml dependencies:` blocks immediately, v0.19.0 ships `aliases: [foundry-agent-harness]` so `apm install` resolves the old name through the new package.

**Why deferred close:** The alias is a one-release courtesy. Keeping it forever would (a) leave two valid names in tooling output (`apm list` etc.), (b) keep stale references in consumer search results, and (c) blur the canonical name in support conversations.

**Consumer migration (one-line edit):**

```diff
 dependencies:
   apm:
-    - sathik11/foundry-agent-skillpack/foundry-agent-harness
+    - sathik11/foundry-agent-skillpack/foundry-agent-skillpack
```

The GitHub repo was also renamed from `Foundry-Hosted-Agent-Skill` to `foundry-agent-skillpack` in v0.20.0. GitHub auto-redirects old URLs, so existing clone URLs, raw-file links, and PR/issue history continue to work.

**Close-out:** Remove the `aliases:` line from `foundry-agent-skillpack/apm.yml` in v0.23 (deferred past v0.22.0 so the alias survives the TD-23 close-out release). Bump major-or-minor per usual policy. Add a final-warning note to the release notes pointing here.

## ~~TD-23 — Inbound firewall coverage for Teams / M365 Copilot → private Foundry agent~~ **(CLOSED in v0.22.0)**

**Status (v0.22.0):** Closed. The published-bot silent-fail mode (typing indicator → no reply) on private Foundry accounts is now covered end-to-end by:

- [foundry-teams-workiq/inbound-firewall.md](.apm/skills/foundry-teams-workiq/inbound-firewall.md) — 8-section runbook covering the architecture, decision matrix across APIM v2 / YARP / AppGW+APIM, paste-ready `<validate-jwt>` policy with verbatim `login.botframework.com` OIDC config, prereqs checklist (Key Vault-backed cert because v2 tiers don't support free managed cert, plus the Microsoft-suspended-through-2026-06-30 status), firewall worksheet, 3-probe verification, 6-row failure-mode table, anti-patterns.
- [foundry-teams-workiq/scripts/templates/apim-v2-vnet-integrated.bicep](.apm/skills/foundry-teams-workiq/scripts/templates/apim-v2-vnet-integrated.bicep) — paste-ready Bicep scaffold for APIM StandardV2 + outbound VNet integration + custom domain (KV-backed cert) + the API/operation/policy/product wiring. `@allowed` constrains SKU to `StandardV2` / `PremiumV2` (BasicV2 explicitly NOT supported for VNet integration per MS Learn). Subnet delegation `Microsoft.Web/serverFarms`. Outputs include the messaging endpoint URL the operator pastes into Bot Service.
- [foundry-teams-workiq/scripts/render-apim-policy.sh](.apm/skills/foundry-teams-workiq/scripts/render-apim-policy.sh) — emits the canonical inbound policy XML for non-Bicep deploys; `--inline` mode substitutes APIM named-value placeholders with concrete values from `agent-status.json` + `agent-capabilities.yaml`. Policy XML is byte-identical to the Bicep `<policies>` block and the canonical block in `inbound-firewall.md` (three sources, one truth).
- [foundry-teams-workiq/scripts/probe-inbound-chain.sh](.apm/skills/foundry-teams-workiq/scripts/probe-inbound-chain.sh) — 3-probe verifier (TLS smoke / missing-auth 401 / synthetic-invalid-JWT 401). On full pass with `--stamp`, writes `publish.inbound_chain` into `agent-status.json` (custom FQDN, backend URL, probe timestamp, verdict).
- Additive `publish.inbound_chain` block in [agent-status-schema.md](.apm/skills/foundry-deploy/agent-status-schema.md#publish--written-by-publish-teams-and-configure-rbac---post-publish-td-2) v1.2 (no `schema_version` bump — additive only; `agent_status.py` `ALLOWED_SECTIONS` already contains `"publish"`).
- New Step 0a in [`/publish-teams`](.apm/prompts/publish-teams.prompt.md) branches on `network.class == "byo_vnet"` OR Foundry `publicNetworkAccess == "Disabled"` and prints the inbound-firewall.md handoff banner before preflight. The `BYO_VNET_PUBLIC_BOT_MISMATCH` gate in `preflight-publish.sh` now has a documented exception path: stand up the inbound chain → override with rationale.
- Cross-skill callouts: [foundry-prod-readiness/networking.md § Inbound](.apm/skills/foundry-prod-readiness/networking.md#inbound--teams--m365-copilot--private-foundry-agent) explains why `Bot Service "Public Access disabled"` only blocks Direct Line (not the Channel Adapter that delivers Teams messages); the firewall allowlist table gains `smba.trafficmanager.net` + `login.botframework.com` for the outbound reply path. [foundry-prod-readiness/network-troubleshooter.md § Symptom triage](.apm/skills/foundry-prod-readiness/network-troubleshooter.md#symptom-triage) routes the silent-typing symptom to inbound-firewall.md. [foundry-failure-modes/SKILL.md F-20](.apm/skills/foundry-failure-modes/SKILL.md#publish--channel-failures) documents the inbound + outbound legs of the silent failure.

**Original gap:** Foundry accounts with `publicNetworkAccess=Disabled` (BYO VNet or managed VNet "Allow only approved") publish cleanly to Teams via `/publish-teams`. The Bot Service messaging endpoint accepts a URL but does not validate it can be reached from the Bot Framework Channel Adapter's public-backbone IPs (Teams service tag `52.112.0.0/14`, `52.122.0.0/15`). The Channel Adapter then drops activities silently when it cannot reach the registered endpoint. Operators saw: `@mention` succeeded, typing indicator appeared, reply never came; no error in Foundry traces, no entry in App Insights, no 4xx anywhere obvious. The publish itself stayed green because Bot Service's "Test in Web Chat" hits Direct Line (a separate REST path that was never blocked) — a textbook silent-fail mode.

**Why now:** Two community write-ups raised the visibility (Matt Felton on the silent-publish-success symptom; Graeme Foster on the outbound reply FQDN allowlisting requirement under managed VNet "Allow only approved"). The fix surface is small (one doc + one Bicep + two scripts + 4 callouts) and the closure is hard-mechanical (probe script returns non-zero on any of the three failures), so the gap was promoted from "open in roadmap" to v0.22.0 close-out.

**Close-out completed:**
- ✅ `inbound-firewall.md` shipped (~280 lines, 8 sections)
- ✅ `apim-v2-vnet-integrated.bicep` shipped (StandardV2 default, PremiumV2 allowed; Key Vault cert path)
- ✅ `render-apim-policy.sh` shipped (placeholder mode + `--inline` substitution)
- ✅ `probe-inbound-chain.sh` shipped (3 probes + optional `--stamp` writes to agent-status)
- ✅ `agent-status-schema.md` v1.2 additive `publish.inbound_chain` (no schema_version bump)
- ✅ `/publish-teams` Step 0a inbound-chain branch
- ✅ `networking.md` Bot Service asymmetry callout + reply-path allowlist entries
- ✅ `network-troubleshooter.md` symptom triage entry
- ✅ `foundry-failure-modes/SKILL.md` F-20 + quick-triage row

