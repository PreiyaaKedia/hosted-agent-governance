# Foundry Agent Skillpack

> **The end-to-end skillpack for Microsoft Foundry hosted agents.** Plan, deploy, govern, evaluate, and audit hosted and prompt agents on Foundry — with persona-aware preflight, durable per-agent state, and a read-only drift detector.

[![Docs](https://img.shields.io/badge/docs-foundry--agent--skillpack-6c47ff)](https://foundry-agent-skillpack.example.com)
[![APM](https://img.shields.io/badge/APM-package-blue)](https://microsoft.github.io/apm/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **v0.20.0 repo rename.** The GitHub repo was renamed from `Foundry-Hosted-Agent-Skill` to [`foundry-agent-skillpack`](https://github.com/sathik11/foundry-agent-skillpack) to match the primary package name. GitHub auto-redirects old URLs. The engineering package was previously renamed from `foundry-agent-harness` → `foundry-agent-skillpack` in v0.19.0; `aliases: [foundry-agent-harness]` still ships through this release (slated to drop in v0.23 — see [TD-19](./foundry-agent-skillpack/TECHNICAL_DEBT.md#td-19--package-rename-foundry-agent-harness--foundry-agent-skillpack)).

📖 **[View the full documentation site →](https://foundry-agent-skillpack.example.com)** *(Azure Static Web Apps)*

---

## What this is

Two installable APM packages plus a hosted documentation site:

- **`foundry-agent-skillpack/`** — engineering skillpack: 15 skills, 9 slash commands, convergent lifecycle scripts for eval / red-team / drift detection, vendored runtime middleware (guardrails + Purview DLP), per-agent durable state.
- **`foundry-agent-playbook/`** — opt-in: 2 runnable samples (`learn-agent`, `langgraph-chat-sample`) and 6 end-to-end recipes covering greenfield, brownfield, knowledge + Purview, AI Search + scheduled eval, APIM-fronted MCP, and multi-agent orchestration.
- **`docs/`** — Astro Starlight site rendered to Azure Static Web Apps.

## Install

```bash
# 0. (One-time) Initialize apm.yml so APM knows where to deploy skills + prompts.
#    Idempotent — only writes if apm.yml is missing.
[ -f apm.yml ] || cat > apm.yml <<'EOF'
name: my-foundry-project
version: 0.0.1
targets:
  - copilot
  - agent-skills
  - claude
  - cursor
  - windsurf
  - codex
  - gemini
  - opencode
EOF

# 1. Engineering skillpack — knowledge + prompts + scripts
apm install sathik11/foundry-agent-skillpack/foundry-agent-skillpack

# 2. Optional but recommended: playbook (samples + recipes)
apm install sathik11/foundry-agent-skillpack/foundry-agent-playbook
```

> **Already have `apm.yml`?** Add a `targets:` line if missing — APM CLI no longer auto-defaults to `copilot` and refuses to install without one. See [docs → Install → Troubleshooting](https://foundry-agent-skillpack.example.com/getting-started/install/#troubleshooting--no-harness-detected).

After install you'll see:

```
.agents/skills/                    ← 16 skills (15 engineering + 1 fixtures)
.github/prompts/                   ← 9 slash commands
.github/agents/                    ← 1 agent persona
```

## Use it

| You want to… | Run |
|---|---|
| Plan a new agent | `/plan-agent agent_name=… description=…` |
| Run pre-deploy gates + `azd up` | `/prepare-deploy agent_path=agents/<name>` |
| Apply base + capability RBAC after deploy | `/configure-rbac agent_path=agents/<name> agent_name=<name>` |
| Smoke-test the deployed endpoint | `/verify-agent agent_name=<name> test_query="…" agent_path=agents/<name>` |
| Schedule continuous evaluation | `/setup-evals agent_name=<name> agent_path=agents/<name>` |
| Enable Purview middleware | `/setup-purview agent_path=agents/<name>` |
| Publish to Teams / M365 Copilot | `/publish-teams agent_path=agents/<name> agent_name=<name>` |
| Diagnose a failure | `/troubleshoot symptom="…"` |
| Read-only drift reconciliation | `/audit-drift agent_path=agents/<name> agent_name=<name>` |

## What runs in your tenant vs. ours

| Layer | Provider |
|---|---|
| Image build, agent create, version create, identity assignment | `azd ai agent` extension (you run it) |
| Per-capability preflight, RBAC dispatch, drift detection | This skillpack's prompts (your coding agent runs them) |
| Foundry-native eval rules, scheduled eval, cloud red-team | Convergent lifecycle scripts in this skillpack (`ensure_*` pattern) |
| Runtime guardrails (middleware, Content Safety, Purview DLP) | Vendored Python middleware — copied into your agent's container |
| Knowledge sources, MCP servers, network class | Your Azure resources; skillpack verifies and grants RBAC |

## Repo layout

```
foundry-agent-skillpack/
├── foundry-agent-skillpack/        # Engineering package (skills + prompts + scripts)
│   ├── apm.yml
│   ├── README.md
│   ├── TECHNICAL_DEBT.md
│   └── .apm/
│       ├── skills/               # 15 skills
│       ├── prompts/              # 9 slash commands
│       ├── agents/               # 1 agent persona
│       └── instructions/
├── foundry-agent-playbook/       # Fixtures + recipes (opt-in)
│   ├── apm.yml
│   ├── README.md
│   └── .apm/skills/foundry-agent-playbook/
│       ├── samples/             # learn-agent, langgraph-chat-sample
│       └── recipes/              # 5 end-to-end walkthroughs
├── docs/                         # Astro Starlight docs site
├── ROADMAP.md
├── TESTING.md
└── TESTING_SCENARIOS.md
```

## Where to start

| You are… | Read |
|---|---|
| New to Foundry hosted agents — building from scratch | [Recipe 01 — Greenfield Quickstart](foundry-agent-playbook/.apm/skills/foundry-agent-playbook/recipes/01-greenfield-quickstart.md) |
| Already have working agent code, want to host it on Foundry | [Recipe 02 — Brownfield Onboarding](foundry-agent-playbook/.apm/skills/foundry-agent-playbook/recipes/02-brownfield-onboarding.md) |
| Want to validate the package end-to-end against a real Foundry project | [TESTING_SCENARIOS.md](TESTING_SCENARIOS.md) |
| Just want to smoke-test that `apm install` works | [TESTING.md](TESTING.md) |

## What's coming

See [ROADMAP.md](ROADMAP.md). Highlights for the next minor release:

- **TD-14 — External persistence for Invocations agents** (Cosmos / Redis patterns).
- **Daily docs-scan workflow** (catches Foundry preview drift).
- **`/setup-evals` writes to `agent-status.json` `evals` block**.

## What this is not

- Not a runtime. Your agent runs in Foundry's container; the skillpack is build/deploy/audit-time only.
- Not a replacement for `azd ai agent`. The skillpack validates and dispatches; `azd up` deploys.
- Not Microsoft-published. Community work tracking the Foundry hosted-agent surface — see [ROADMAP.md](ROADMAP.md) for the path to Microsoft Learn submission.

## Contributing

See the [Contributing page on the docs site](https://foundry-agent-skillpack.example.com/contributing/) (or [docs/src/content/docs/contributing.md](docs/src/content/docs/contributing.md) on disk).

## License

[MIT](LICENSE)
