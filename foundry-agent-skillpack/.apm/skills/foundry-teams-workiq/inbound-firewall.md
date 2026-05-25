# Inbound firewall for Teams `@mention` → private Foundry agent

> Owned by [`/publish-teams`](../../prompts/publish-teams.prompt.md) Step 0 (BYO-VNet branch). Closes [TD-23](../../../TECHNICAL_DEBT.md#td-23--inbound-firewall-coverage-for-teams--m365-copilot--private-foundry-agent).
>
> **The problem this solves.** When a Foundry agent is published to Teams/M365 Copilot, the Bot Framework Channel Adapter calls the agent's `activityprotocol` endpoint **from the public Microsoft backbone** (source IPs in the [Teams Office 365 service tag](https://learn.microsoft.com/microsoft-365/enterprise/urls-and-ip-address-ranges) — primarily `52.112.0.0/14` and `52.122.0.0/15`). If your Foundry account has `publicNetworkAccess=Disabled` (BYO-VNet + Private Endpoint), that call **lands on a private IP that Teams cannot reach**. The publish gesture succeeds, the M365 admin approves, and the `@mention` goes silently nowhere.
>
> The preflight gate `BYO_VNET_PUBLIC_BOT_MISMATCH` in [`preflight-publish.sh`](scripts/preflight-publish.sh) catches the configuration but is not the fix. This document is the fix.

## When to read this

You are here because one of the following is true:

- `/publish-teams` Step 0 branched here (network class = `byo_vnet` **or** Foundry `publicNetworkAccess=Disabled`).
- You hit failure-mode **F-26 — Teams `@mention` succeeds, no reply** in [foundry-failure-modes/SKILL.md](../foundry-failure-modes/SKILL.md).
- You're capacity-planning a private Foundry deployment and need to know what to put between Microsoft's public Channel Adapter and your private agent.

## Architecture

```
   Teams / Copilot client                            Microsoft 365 backbone
            │                                                 │
            └───────► Bot Framework Channel Adapter ──────────┤  signs JWT
                                                              │  (iss=api.botframework.com,
                                                              │   aud=<bot_app_id>)
                                                              │
                                              public IP: Teams service tag
                                                              │
                                                              ▼
                                            ┌──────── Corporate edge ────────┐
                                            │                                │
                                            │   DNAT (firewall / WAF)        │
                                            │   • restrict src to Teams CIDR │
                                            │   • forward 443 → APIM v2 IP   │
                                            │                                │
                                            └────────────────┬───────────────┘
                                                             │
                                            ┌─────── APIM v2 (StandardV2) ────┐
                                            │   gateway: PUBLIC inbound       │
                                            │   custom domain: bot.contoso…   │
                                            │   cert: KV-backed (system MI)   │
                                            │   inbound policy:               │
                                            │     <validate-jwt>              │
                                            │       openid-config             │
                                            │         botframework            │
                                            │       audience = bot_app_id     │
                                            │       issuer = api.botframework │
                                            │     <set-backend>               │
                                            │       Foundry PE FQDN           │
                                            │                                 │
                                            │   VNet integration (OUTBOUND)   │
                                            │   delegated subnet              │
                                            │   → Microsoft.Web/serverFarms   │
                                            └──────────────────┬──────────────┘
                                                               │
                                                  privatelink.services.ai.azure.com
                                                               │
                                                               ▼
                                            ┌──────── Foundry account (PE) ────────┐
                                            │   publicNetworkAccess = Disabled     │
                                            │   /api/projects/<p>/agents/<a>/      │
                                            │       endpoint/protocols/            │
                                            │       activityprotocol               │
                                            └──────────────────────────────────────┘
```

Three properties make this work:

1. **JWT validation is unavoidable.** Bot Framework signs every Channel call with a JWT issued by `https://api.botframework.com`. Anything that just IP-restricts to the Teams service tag without validating the JWT is spoofable. Only APIM (`<validate-jwt>`) and AppGW WAF v2 with an Azure Functions / containerized validator can do this. Stock AppGW v2 cannot validate Bot Framework JWTs — its native validator is Entra-only.
2. **APIM v2 outbound VNet integration is one-way.** Inbound stays public (that is what Teams needs); outbound rides the delegated subnet to reach the Foundry Private Endpoint. This is **virtual network integration** ([MS Learn](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)), not **virtual network injection**. Injection is Premium-v2-only and is overkill for this scenario.
3. **The Foundry agent's Entra Agent Identity *is* the `bot_app_id`.** The audience claim APIM validates is exactly the `clientId` field of `agent.identity` after publish ([MS Learn — Configure and share your agent](https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent#understand-the-agent-object-model)). The skillpack reads it from `agent-status.json` → `publish.bot_app_id`. There is no separate Entra app to register.

## Decision matrix

Three viable approaches. Pick before you build.

| Approach | Strengths | Weaknesses | Use when |
|---|---|---|---|
| **APIM v2 (StandardV2)** + VNet integration (this doc's default) | One resource handles TLS, JWT validation, backend routing, outbound to PE. ~$700/mo list. Paste-ready Bicep below. | Adds a new managed service to operate. SLA 99.95% single-region. | **Default** — recommended for new builds. The shipped Bicep is this path. |
| **YARP** (self-hosted reverse proxy, containers) | Cheapest. Full code control. | You operate it, scale it, patch it, monitor it. You write the JWT validation in C#/Go. | Existing platform team with reverse-proxy fleet already in place. Skillpack does **not** ship this; see [Graeme Foster's reference](https://garyfoster.com/2025/01/30/foundry-agents-corporate-firewall/) for a worked example. |
| **AppGW WAF v2** (front) + APIM v2 (back) | WAF rules + JWT validation. OWASP CRS coverage. | Two services, two cost centers, two operations runbooks. AppGW alone *cannot* validate Bot JWTs — APIM is still required. | Workloads with a tenant policy that mandates WAF at the public edge. |

**APIM classic** (Developer / Basic / Standard / Premium — non-v2 tiers) is **not** the path going forward. It runs on a deprecating SKU family; new build-outs should pick StandardV2 or PremiumV2. Existing classic deployments can use the same `<validate-jwt>` policy — see [Matt Felton's deep dive](https://blog.matthewfelton.com/2025/12/microsoft-foundry-publishing-agents-to-teams-deep-dive-part-1/) for the classic-tier Bicep equivalent. Skillpack does not ship a classic Bicep.

## Paste-ready APIM `<validate-jwt>` policy

This is the canonical inbound policy. Drop it into the API or Operation scope (Product scope works too if you want one product to cover multiple bots).

```xml
<policies>
  <inbound>
    <base />
    <!--
      Bot Framework Channel Adapter sends a JWT in Authorization: Bearer <token>.
      issuer  = https://api.botframework.com
      audience = bot_app_id (== agent.identity.clientId after publish)
      openid-config = https://login.botframework.com/v1/.well-known/openidconfiguration

      validate-connectivity="false" — APIM v2 with VNet integration may not have
      a public DNS path during cold start; the policy fetches and caches the
      OIDC document on first call. Cached for ~1h with periodic refresh per
      MS Learn (validate-jwt-policy doc, "Elements" section).
    -->
    <validate-jwt header-name="Authorization"
                  failed-validation-httpcode="401"
                  failed-validation-error-message="Unauthorized. Bot Framework JWT required."
                  require-scheme="Bearer"
                  require-expiration-time="true"
                  require-signed-tokens="true"
                  clock-skew="300">
      <openid-config url="https://login.botframework.com/v1/.well-known/openidconfiguration"
                     validate-connectivity="false" />
      <audiences>
        <audience>{{bot-app-id}}</audience>   <!-- named value, set from agent-status.json -->
      </audiences>
      <issuers>
        <issuer>https://api.botframework.com</issuer>
      </issuers>
    </validate-jwt>

    <!-- Route to the Foundry Private Endpoint FQDN. APIM v2's VNet integration
         resolves this via the privatelink.services.ai.azure.com zone linked
         to the same VNet as the integration subnet. -->
    <set-backend-service base-url="https://{{foundry-account-fqdn}}/api/projects/{{project-name}}/agents/{{agent-name}}/endpoint/protocols/activityprotocol" />

    <!-- Preserve the original Host header so APIM's outbound TLS hits the right SNI. -->
    <set-header name="Host" exists-action="override">
      <value>{{foundry-account-fqdn}}</value>
    </set-header>
  </inbound>
  <backend>
    <forward-request timeout="120" />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
```

Named values to set (in APIM → Named values):

| Named value | Source | How |
|---|---|---|
| `bot-app-id` | `agent-status.json` → `publish.bot_app_id` | `jq -r '.publish.bot_app_id' agents/<n>/agent-status.json` |
| `foundry-account-fqdn` | Foundry account FQDN | `<account-name>.services.ai.azure.com` |
| `project-name` | Foundry project name | from `agent.yaml` / `agent-capabilities.yaml` |
| `agent-name` | Deployed agent name | `agents/<n>/agent.yaml` |

[`scripts/render-apim-policy.sh`](scripts/render-apim-policy.sh) emits this XML with the named-value placeholders left in place (so you paste into APIM, then set the named values once). Or fully-rendered with `--inline` for one-shot import.

## Bicep — APIM v2 + VNet integration

The shipped scaffold is [`scripts/templates/apim-v2-vnet-integrated.bicep`](scripts/templates/apim-v2-vnet-integrated.bicep). Parallel pattern to [`foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep`](../foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep) — paste-ready, no `az` mutations, designed to drop into `./infra/` and let `azd up` own the deploy.

What it provisions:

- `Microsoft.ApiManagement/service` (StandardV2) with system-assigned managed identity.
- Custom domain hostname configuration backed by an Azure Key Vault secret (system MI must already have `Key Vault Secrets User` on the KV — see § Prereqs).
- One API with the inbound policy above (rendered via `render-apim-policy.sh` or copy-pasted).
- One Product `bot-channel-ingress` with subscription-required = false (Bot Framework does not send a subscription key).
- VNet integration sub-resource pointing at a subnet you pass in.

What it does NOT provision (intentionally — separate ownership):

- The VNet itself or the delegated subnet (your network team or the [`byo-vnet-with-pe.bicep`](../foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep) scaffold owns those).
- The Foundry Private Endpoint (also owned by the BYO VNet scaffold).
- The Key Vault or the cert in it (BYO cert workflow — operator uploads PFX, RBAC-grants the APIM MI).
- The corporate edge DNAT / firewall (your network team).
- Public DNS for the custom domain (operator-owned; the Bicep outputs the gateway IP for the A record).

## Prerequisites checklist

Before `azd up` on the Bicep:

- [ ] **APIM v2 SKU available in the target region.** Not every region carries StandardV2; check [v2 service tiers overview](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview).
- [ ] **Delegated subnet exists.** /27 minimum, /24 recommended ([MS Learn](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)). Delegation: `Microsoft.Web/serverFarms`. The `Microsoft.Web` RP must be registered in the subscription.
- [ ] **NSG associated with the subnet.** Outbound TCP/443 to `Storage` and `AzureKeyVault` service tags is required by APIM. Inbound NSG rules are **not enforced** in integration mode (per docs) — don't waste time tightening them.
- [ ] **Subnet is dedicated.** No other APIM instance may share it.
- [ ] **Private DNS zone `privatelink.services.ai.azure.com` linked to the integration VNet.** Without this, APIM's outbound DNS resolves the Foundry FQDN to a public IP and never reaches the PE.
- [ ] **Key Vault hosts the TLS cert as a secret (PFX).** APIM v2 does **not** support the free managed cert (per [MS Learn — domain certificate options](https://learn.microsoft.com/azure/api-management/configure-custom-domain#domain-certificate-options): "Not supported in the v2 tiers"). KV + system MI is the recommended path.
- [ ] **System MI has `Key Vault Secrets User` on the KV** (or `Get` access policy if you're on the legacy access-policy model).
- [ ] **`agent-status.json` `publish.bot_app_id` is populated.** This is the audience claim. `/publish-teams` Step 4 stamps it; do not deploy APIM until publish has run at least once.

## Firewall worksheet template

Hand this to your network team. The values are what they need to allow:

```
Source CIDR (inbound)                     Destination                       Port  Notes
─────────────────────────────────────     ───────────────────────────────   ────  ──────────────────────────────────
Teams service tag (52.112.0.0/14)         APIM v2 gateway public IP         443   Channel Adapter → bot inbound
Teams service tag (52.122.0.0/15)         APIM v2 gateway public IP         443   Additional Teams CIDR block

# Outbound from APIM's delegated subnet — covered by Azure Firewall app rules
# OR the subnet NSG service tags below.

Source: APIM integration subnet           Destination FQDN/Service Tag      Port  Notes
─────────────────────────────────────     ───────────────────────────────   ────  ──────────────────────────────────
APIM integration subnet                   Storage (service tag)             443   APIM dependency
APIM integration subnet                   AzureKeyVault (service tag)       443   APIM dependency (also cert pull)
APIM integration subnet                   login.botframework.com            443   OIDC metadata + JWKS for validate-jwt
APIM integration subnet                   privatelink.services.ai.azure.com  443  Foundry PE backend (private DNS)

# Outbound from the agent itself (Foundry-managed VNet OR your BYO subnet)
# — these are the "silent reply failure" FQDNs. Without them the agent runs
# but the channel reply never reaches the user.

Source: Foundry agent egress              Destination FQDN                  Port  Notes
─────────────────────────────────────     ───────────────────────────────   ────  ──────────────────────────────────
Foundry agent egress                      smba.trafficmanager.net           443   Bot Service reply ingestion
Foundry agent egress                      login.botframework.com            443   Bot Service token mint
Foundry agent egress                      login.microsoftonline.com         443   Entra Agent ID token mint
```

`*.tenant.api.powerplatform.com` may also appear in egress traces on VNet-injected Foundry agents post-publish. Purpose is under investigation upstream; the recommendation today is **observe before allowlisting** — let the connection fail closed, capture the FQDN in Azure Firewall logs, then decide. Tracked under TD-23 follow-on.

## Verification probe

After the Bicep deploys + the firewall rules are in place + the operator publishes via `/publish-teams`, run [`scripts/probe-inbound-chain.sh`](scripts/probe-inbound-chain.sh):

```bash
.agents/skills/foundry-teams-workiq/scripts/probe-inbound-chain.sh \
  agents/<name> \
  bot.contoso.com   # the APIM custom domain
```

Three probes execute and **all three must pass** before declaring inbound chain healthy:

1. **TLS smoke** — `curl -vI https://<custom-domain>` confirms the custom cert chains to a public root. Catches misconfigured KV cert / missing intermediates / DNS pointing at the wrong IP.
2. **Missing-auth 401** — `curl -X POST https://<custom-domain>/messages` with no Authorization header MUST return 401 with the `failed-validation-error-message`. Confirms the policy is bound to the API and is rejecting unauthenticated traffic. If you get 200 / 502 / 404 here, the policy isn't attached.
3. **Synthetic-invalid-JWT 401** — POST with `Authorization: Bearer ey<garbage>` MUST also return 401. Confirms `<validate-jwt>` actually parses the token (a misconfigured policy can pass strings through). The OIDC config must have been fetched at this point — check APIM diagnostic logs for the JWKS pull.

The script stamps `publish.inbound_chain` in `agent-status.json` on full pass. Re-run after any firewall / DNS / APIM policy change.

## Failure-mode lookup

| Symptom | Diagnose | Fix |
|---|---|---|
| Teams `@mention` succeeds (typing indicator), no reply, no agent trace | APIM not in the path (Bot Service messaging endpoint not pointing at `https://<custom-domain>/messages`) | Re-check Bot Service resource → Configuration → Messaging endpoint. Must be the APIM custom domain, not the Foundry FQDN. |
| Probe 1 fails (TLS) | KV cert not pulled or DNS A record points at wrong IP | Check APIM → Custom domains → certificate status; check APIM → Managed identities → KV role assignment; verify DNS A record matches Bicep output `apimGatewayPublicIp` |
| Probe 2 returns 200 / 404 / 502 | Inbound policy not attached to the API or wrong scope | Re-import the API from the Bicep; verify policy is at API scope, not just Product |
| Probe 3 returns 200 (passes invalid token) | `<validate-jwt>` element typo (case-sensitive); audience or issuer mismatch | Compare rendered XML against the canonical block in this doc; re-run `render-apim-policy.sh` |
| Probe 2/3 returns 401 but Teams `@mention` *also* returns silent failure | Bot Framework token aud mismatch — the JWT carries the bot's `clientId` not the `appId` (legacy bots) | Confirm `agent-status.json` `publish.bot_app_id` matches the value Bot Service shows on its Configuration page. The Foundry-published agent uses Entra Agent Identity `clientId`. |
| Reply text never arrives but invocation traces show success | Agent egress missing `smba.trafficmanager.net` / `login.botframework.com` | Update outbound firewall rules per the worksheet template above. This is the "silent reply" failure mode (F-26). |

## Do NOT

- **Do NOT** terminate TLS at AppGW and forward HTTP to APIM. APIM v2's policy expects to validate the JWT against TLS-presented connections; mid-path TLS termination breaks the OIDC connectivity check in some tenants and complicates cert rotation in all of them.
- **Do NOT** use APIM's free managed cert. Per MS Learn it is not supported in v2 tiers, **and** managed-cert creation is globally suspended through 30 June 2026 ([breaking change](https://learn.microsoft.com/azure/api-management/breaking-changes/managed-certificates-suspension-august-2025)).
- **Do NOT** put the agent's PE in the same subnet as the APIM integration. APIM v2's delegated subnet is dedicated — sharing breaks deploy. Use the two-subnet pattern in [`byo-vnet-with-pe.bicep`](../foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep).
- **Do NOT** skip the probe before declaring publish healthy. The publish gate (`/publish-teams` Step 4) only confirms identity-flip happened; it does NOT confirm Teams can actually reach the bot. The probe is the only thing that does.
- **Do NOT** validate the JWT against `login.microsoftonline.com` (Entra). Bot Framework runs its own IdP at `login.botframework.com`. The two are different OIDC issuers; using the Entra metadata endpoint will reject every legitimate Bot Service call.

## Cross-skill references

- The publish flow this hooks into → [publish-flow.md](publish-flow.md) and [`/publish-teams`](../../prompts/publish-teams.prompt.md)
- BYO VNet + Foundry PE scaffold → [foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep](../foundry-prod-readiness/scripts/network/templates/byo-vnet-with-pe.bicep)
- Network classes + FQDN allowlist baseline → [foundry-prod-readiness/networking.md](../foundry-prod-readiness/networking.md)
- Silent-reply triage → [foundry-prod-readiness/network-troubleshooter.md](../foundry-prod-readiness/network-troubleshooter.md)
- Known failure modes catalog → [foundry-failure-modes/SKILL.md](../foundry-failure-modes/SKILL.md)
- `publish.inbound_chain` schema → [foundry-deploy/agent-status-schema.md § publish](../foundry-deploy/agent-status-schema.md#publish--written-by-publish-teams-and-configure-rbac---post-publish-td-2)

## External references

- [Matt Felton — Microsoft Foundry: Publishing Agents to Teams Deep Dive Part 1](https://blog.matthewfelton.com/2025/12/microsoft-foundry-publishing-agents-to-teams-deep-dive-part-1/) — classic APIM walk-through + Bot Service mechanics
- [Graeme Foster — Foundry Agents and Custom Engine Agents through the Corporate Firewall](https://garyfoster.com/2025/01/30/foundry-agents-corporate-firewall/) — YARP reference + outbound reply FQDN discovery
- [MS Learn — Integrate APIM v2 with a private virtual network for outbound connections](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [MS Learn — validate-jwt policy](https://learn.microsoft.com/azure/api-management/validate-jwt-policy)
- [MS Learn — Bot Connector API authentication](https://learn.microsoft.com/azure/bot-service/rest-api/bot-framework-rest-connector-authentication)
- [MS Learn — Configure and share your Foundry agent](https://learn.microsoft.com/azure/foundry/agents/how-to/configure-agent)
