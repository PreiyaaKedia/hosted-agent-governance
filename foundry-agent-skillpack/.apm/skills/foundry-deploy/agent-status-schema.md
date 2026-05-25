# `agent-status.json` — durable per-agent state

Per-agent record of what happened during the last lifecycle run. Lives next to `agent.yaml` (or `agent-definition.yaml`).

> **Three readers minimum rule.** This file exists because three prompts need it:
> - `/prepare-deploy` writes preflight + network detection results.
> - `/configure-rbac` writes identity discovery + per-capability grant outcomes.
> - `/verify-agent` reads everything to gate publish, runs drift detection, writes `verify` block.
>
> When a fourth reader (`/audit-drift`, planned) lands, the file pays for itself further. Until then this file justifies its existence on the strength of `verify` reading what `configure-rbac` wrote.

## Where it lives

```
agents/<name>/
├── agent.yaml
├── agent-capabilities.yaml
├── agent-status.json           ← this file (NOT secret; commit it)
├── Dockerfile
└── …
```

**Commit it.** It contains no credentials — only object IDs, principal IDs, role names, network classifications, hashes. Drift detection requires git history. If your tenant policy treats principal IDs as sensitive, add it to `.gitignore` and accept losing drift detection.

## File header

Every file starts with `_schema_url` and `schema_version` so consumers can validate without out-of-band lookups:

```json
{
  "_schema_url": "https://github.com/sathik11/foundry-agent-skillpack/blob/main/foundry-agent-skillpack/.apm/skills/foundry-deploy/agent-status-schema.md",
  "schema_version": 1,
  "agent_name": "feedback-harvester",
  "agent_path": "agents/feedback-harvester",
  "agent_kind": "hosted",
  "last_updated": "2026-05-14T10:30:00Z",
  "last_actor": "user@contoso.com"
}
```

## Top-level sections

All sections are **optional**. A section appears once a prompt has written to it. Within a section, fields are **additive** — the helper merges, never replaces wholesale (use `--path` for surgical writes).

### `identities` — written by `/configure-rbac` Step 1

```json
"identities": {
  "project_mi_principal_id": "0f8d7f71-...",
  "agent_principal_id":      "1a2b3c4d-...",
  "discovered_at":           "2026-05-14T10:00:00Z",
  "discovered_by":           "user@contoso.com"
}
```

### `deploy` — written by `/verify-agent` Step 0 (after `azd ai agent show`)

```json
"deploy": {
  "version":      "v3",
  "image_tag":    "myacr.azurecr.io/agent:20260514-1030",
  "deployed_at":  "2026-05-14T10:15:00Z",
  "azd_env":      "prod",
  "endpoint":     "https://acct.services.ai.azure.com/api/projects/proj"
}
```

### `preflight` — written by `/prepare-deploy` Step 2.5

Per-capability ✅/⚠/❌ from the gate matrix.

```json
"preflight": {
  "capabilities": {
    "toolbox":      {"verdict": "pass", "detail": "3 mcp servers, all URLs valid"},
    "guardrails":   {"verdict": "pass", "detail": "middleware mode=entry, CS connection 'cs-prod' exists"},
    "fabric":       {"verdict": "warn", "detail": "workspace exists, role recorded for post-deploy"},
    "purview":      {"verdict": "warn", "detail": "toggle status unknown — verify portal manually"}
  },
  "checked_at": "2026-05-14T09:50:00Z"
}
```

### `network` — written by `/prepare-deploy` Step 2.5 from network detection scripts

```json
"network": {
  "class": "managed_vnet",
  "region": "eastus2",
  "foundry": {
    "public_network_access": "Enabled",
    "outbound_mode":         "approved_only",
    "acr_pna":               "Enabled",
    "checked_at":            "2026-05-14T09:55:00Z"
  },
  "sources": {
    "/subscriptions/.../Microsoft.Search/searchServices/kb-prod": {
      "kind":                  "ai_search",
      "public_network_access": "Disabled",
      "default_action":        "Deny",
      "private_endpoints":     1,
      "pe_status":             "Approved",
      "verdict":               "reachable_via_pe",
      "checked_at":            "2026-05-14T09:55:00Z"
    }
  }
}
```

### `rbac` — written by `/configure-rbac` Step 2 + Step 3

```json
"rbac": {
  "phases_completed":  ["phase1_image_pull", "phase2_runtime"],
  "last_grant_at":     "2026-05-14T10:20:00Z",
  "capability_grants": {
    "guardrails.content_safety.cs-prod": {
      "role":       "Cognitive Services User",
      "scope":      "/subscriptions/.../cs-prod",
      "granted_to": "1a2b3c4d-...",
      "granted_at": "2026-05-14T10:21:00Z"
    },
    "knowledge.ai_search.kb-prod": {
      "role":       "Search Index Data Reader",
      "scope":      "/subscriptions/.../kb-prod",
      "granted_to": "1a2b3c4d-...",
      "granted_at": "2026-05-14T10:21:30Z"
    }
  },
  "pending": [
    {
      "key":        "fabric.workspace.sales-analytics",
      "reason":     "Fabric workspace role assignment is print-only (TD-1)",
      "runbook_emitted": true,
      "noted_at":   "2026-05-14T10:22:00Z"
    }
  ]
}
```

### `evals` — written by `foundry-evals/scripts/ensure_*.py`

```json
"evals": {
  "continuous_rule_id":  "continuous-eval-feedback-harvester",
  "scheduled_rule_id":   null,
  "redteam_scan_id":     null,
  "evaluators":          ["intent_resolution", "task_adherence", "indirect_attack", "tool_call_accuracy"],
  "judge_model":         "gpt-5.4-mini-1",
  "last_setup_at":       "2026-05-14T10:25:00Z"
}
```

### `verify` — written by `/verify-agent` Step 5; `last_audit_*` fields written by `/audit-drift`

```json
"verify": {
  "last_run_at":            "2026-05-14T10:28:00Z",
  "last_run_status":        "pass",
  "endpoint_reachable":     true,
  "model_responding":       true,
  "tool_spans_present":     true,
  "guardrail_spans_present": true,
  "smoke_query_response_id": "resp_abc123",
  "capability_results": {
    "toolbox":    {"verdict": "pass", "detail": "microsoft_learn: 4 spans, all 200"},
    "guardrails": {"verdict": "pass", "detail": "5 guardrail.middleware spans, blocked sample refused"}
  },

  // /audit-drift writes these three fields ON TOP of the verify block. They are
  // additive — last_run_at and last_audit_at are independent. Either may be present.
  "last_audit_at":      "2026-05-14T11:00:00Z",
  "audit_summary":      {"pass": 12, "warn": 4, "fail": 1},
  "audit_report_path":  ".audit-reports/feedback-harvester-2026-05-14.md"
}
```

### `drift` — written by `/prepare-deploy`, `/configure-rbac`, `/verify-agent`

The drift block records the `agent-capabilities.yaml` SHA-256 (first 12 chars) at each lifecycle phase. Drift is detected when the hash at one phase differs from the previous.

```json
"drift": {
  "capability_hash_at_preflight": "a3f29c84b1d0",
  "capability_hash_at_rbac":      "a3f29c84b1d0",
  "capability_hash_at_verify":    "a3f29c84b1d0",
  "drift_detected":               false,
  "drift_fields":                 []
}
```

When the hash differs between phases, `drift_detected: true` + `drift_fields` lists the top-level YAML keys that changed (best-effort — diff is line-level).

### `publish` — written by `/publish-teams` and `/configure-rbac --post-publish` (TD-2)

The publish block records the runtime-identity flip that occurs when a Foundry agent is published to a Microsoft 365 / Teams surface. Before publish, invocations carry the **per-agent project identity**; after publish, they carry the **Bot Framework application identity** registered with the Microsoft.BotService resource provider. Capability grants must be re-fanned to the new principal (see [foundry-teams-workiq/publish-flow.md § Step 6](../foundry-teams-workiq/publish-flow.md#step-6--post-publish-rbac-re-fan)).

```json
"publish": {
  "channel":                        "msteams",
  "published_at":                   "2026-06-18T14:22:11Z",
  "bot_app_id":                     "8f3b…-aaaa-…",          // Bot Framework App ID (Entra app registration appId)
  "application_identity_principal_id": "c2e0…-bbbb-…",       // The MSI / SP that invocations now run as
  "agent_identity_model":           "new",                   // "new" (Foundry-managed) | "legacy" (teamsapp)
  "publish_metadata_secret_scan":   "clean",                 // clean | findings (with publish.secret_scan_findings array)
  "m365_admin_approval_status":     "pending",               // pending | approved | rejected | not_required
  "m365_admin_approval_runbook_emitted_at": "2026-06-18T14:22:13Z",
  "rbac_refanned_at":               "2026-06-18T14:35:02Z",  // set by /configure-rbac --post-publish
  "preflight": {
    "bot_service_rp_registered":    true,
    "byo_vnet_public_bot_mismatch": false,                   // true blocks publish unless explicitly overridden
    "evals_continuous_rule_id":     "rule-prd-001",          // gate: must be present
    "purview_enabled":              true                     // gate: must be true
  },
  "inbound_chain": {                                         // additive (v1.2 / 0.22.0); written by foundry-teams-workiq/scripts/probe-inbound-chain.sh --stamp
    "custom_fqdn":                  "bot.contoso.com",       // The APIM custom domain the Bot Service messaging endpoint points at
    "apim_resource_id":             "/subscriptions/…/Microsoft.ApiManagement/service/apim-bots",  // optional
    "backend_url":                  "https://acct.services.ai.azure.com/api/projects/proj/agents/feedback-harvester/endpoint/protocols/activityprotocol",
    "probe_at":                     "2026-06-19T09:11:02Z",
    "probe_verdict":                "pass"                   // pass | fail (re-stamped on each successful probe run)
  }
}
```

Gating rules enforced by `/publish-teams`:

- `preflight.evals_continuous_rule_id` must be non-null (i.e. `/setup-evals continuous` has run).
- `preflight.purview_enabled` must be `true` (i.e. `/setup-purview` has run).
- `preflight.byo_vnet_public_bot_mismatch == false` (or operator override with documented exception).
- `publish_metadata_secret_scan == "clean"` — display name / description / endpoint URLs scanned via regex for secrets, no findings.

## Field naming conventions

- **Timestamps** — RFC 3339 / ISO 8601 UTC with `Z` suffix. The helper stamps these.
- **Dotted keys for capability grants** — `<top_capability>.<sub>.<name>`. Stable enough to diff across runs.
- **Object IDs** — full GUIDs, no `aad_` / `oid_` prefixes.
- **Resource IDs** — full ARM paths.
- **Hashes** — SHA-256 first 12 hex chars (matches `git rev-parse --short=12`).

## What this file is NOT

- ❌ Not a config file. Never read by Foundry runtime.
- ❌ Not a substitute for `agent-capabilities.yaml`. The capabilities file is intent; this file is observed state.
- ❌ Not authoritative for RBAC. `az role assignment list` is. This is a cache + audit trail.
- ❌ Not secret. But also do not log full ARM paths in public CI output if your tenant treats them as sensitive.

## Helper script

[scripts/agent_status.py](scripts/agent_status.py) is the only thing that should write this file. Direct edits or `jq` writes from prompts are an anti-pattern — they bypass schema enforcement, atomic writes, and the merge semantics.

```bash
# Read
python .agents/skills/foundry-deploy/scripts/agent_status.py read \
  --agent-path agents/feedback-harvester [--field rbac.capability_grants]

# Init (idempotent)
python .agents/skills/foundry-deploy/scripts/agent_status.py init \
  --agent-path agents/feedback-harvester --agent-name feedback-harvester --agent-kind hosted

# Update a section (merges into existing)
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path agents/feedback-harvester \
  --section rbac \
  --json '{"phases_completed": ["phase1_image_pull", "phase2_runtime"], "last_grant_at": "2026-05-14T10:20:00Z"}'

# Surgical set at a dotted path
python .agents/skills/foundry-deploy/scripts/agent_status.py update \
  --agent-path agents/feedback-harvester \
  --path verify.last_run_status \
  --json '"pass"'

# Capability hash + drift
python .agents/skills/foundry-deploy/scripts/agent_status.py hash --agent-path agents/feedback-harvester
python .agents/skills/foundry-deploy/scripts/agent_status.py drift --agent-path agents/feedback-harvester
# (drift returns exit 1 + prints diff if capability hash changed since last 'rbac' phase)
```

## Schema migration

When `schema_version` increments:
1. Ship a migration in `agent_status.py` (`_migrate_v{n}_to_v{n+1}`).
2. Helper detects old version on read, runs migration, writes back atomically.
3. Document the change in this file's "Changelog" below.

### Changelog

- **v1** (2026-05-14, package 0.11.0): initial schema with `identities`, `deploy`, `preflight`, `network`, `rbac`, `evals`, `verify`, `drift`.
- **v1.1** (2026-06-18, package 0.20.0): additive `publish` section (TD-2). No breaking changes; consumers that don't read `publish` are unaffected.
- **v1.2** (2026-06-19, package 0.22.0): additive `publish.inbound_chain` block (TD-23). Written by `foundry-teams-workiq/scripts/probe-inbound-chain.sh --stamp` once TLS + missing-auth-401 + invalid-JWT-401 probes all pass against the customer reverse proxy fronting the private Foundry agent. No `schema_version` bump (additive only).
