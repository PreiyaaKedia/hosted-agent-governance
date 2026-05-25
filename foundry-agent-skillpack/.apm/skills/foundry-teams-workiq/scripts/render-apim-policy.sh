#!/usr/bin/env bash
# Emit the APIM inbound <validate-jwt> + <set-backend> policy XML for fronting
# a private Foundry agent's Activity Protocol endpoint.
#
# SKU-agnostic — the policy XML is identical for APIM classic and APIM v2; the
# difference is in the service tier (BasicV2/StandardV2 cannot do injection,
# only integration). This script just renders the XML; the deploy boundary
# stays with the operator (paste into APIM portal / az apim) or with Bicep.
#
# Tracked: TD-23.
#
# Usage:
#   render-apim-policy.sh <agent_path> [--inline]
#
#   <agent_path>    Path to the agent folder containing agent-status.json
#   --inline        Substitute named-value placeholders with concrete values
#                   read from agent-status.json + agent-capabilities.yaml.
#                   Default (no flag): leave APIM named-value placeholders
#                   ({{bot-app-id}}, {{foundry-account-fqdn}}, etc.) in place
#                   so you paste into APIM once and configure the named values
#                   there. Preferred path — supports key rotation without redeploy.
#
# Reads (no writes):
#   <agent_path>/agent-status.json     → .publish.bot_app_id (required)
#   <agent_path>/agent-capabilities.yaml → project_name, agent_name, foundry account
#   <agent_path>/agent.yaml             → fallback for the same fields
#
# Exit codes:
#   0  success — XML on stdout
#   2  missing input files
#   3  missing required tools
#   4  --inline requested but publish.bot_app_id is empty (publish not run yet)

set -euo pipefail

AGENT_PATH="${1:?usage: render-apim-policy.sh <agent_path> [--inline]}"
MODE="${2:-}"

STATUS_FILE="$AGENT_PATH/agent-status.json"
CAPS_FILE="$AGENT_PATH/agent-capabilities.yaml"
AGENT_YAML="$AGENT_PATH/agent.yaml"

if [[ ! -f "$STATUS_FILE" ]]; then
  echo "[x] $STATUS_FILE not found." >&2
  echo "    Run /prepare-deploy and /publish-teams first." >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "[x] missing: jq" >&2; exit 3; }

# Canonical policy XML — kept in lockstep with the Bicep scaffold
# (templates/apim-v2-vnet-integrated.bicep) and the canonical block in
# inbound-firewall.md. If you change one, change all three.

read -r -d '' POLICY_XML <<'POLICY_EOF' || true
<policies>
  <inbound>
    <base />
    <!--
      Bot Framework Channel Adapter sends a JWT in Authorization: Bearer <token>.
      issuer   = https://api.botframework.com
      audience = bot_app_id  (== agent.identity.clientId after publish)
      openid-config = https://login.botframework.com/v1/.well-known/openidconfiguration

      validate-connectivity="false" — APIM v2 with VNet integration may not have
      a public DNS path during cold start; the policy fetches and caches the
      OIDC document on first call.
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
        <audience>{{bot-app-id}}</audience>
      </audiences>
      <issuers>
        <issuer>https://api.botframework.com</issuer>
      </issuers>
    </validate-jwt>
    <set-backend-service base-url="https://{{foundry-account-fqdn}}/api/projects/{{project-name}}/agents/{{agent-name}}/endpoint/protocols/activityprotocol" />
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
POLICY_EOF

if [[ "$MODE" != "--inline" ]]; then
  # Placeholder mode: print as-is.
  printf '%s\n' "$POLICY_XML"
  exit 0
fi

# ─── Inline mode: substitute APIM named-value placeholders with concrete values ──

BOT_APP_ID=$(jq -r '.publish.bot_app_id // ""' "$STATUS_FILE")
if [[ -z "$BOT_APP_ID" || "$BOT_APP_ID" == "null" ]]; then
  echo "[x] --inline requires publish.bot_app_id in $STATUS_FILE" >&2
  echo "    Run /publish-teams Step 4 first so the bot app id is stamped." >&2
  exit 4
fi

# Project name + agent name + Foundry account FQDN — best-effort YAML extraction.
# These are required for the backend URL; we exit non-zero rather than guess.
yaml_get() {
  # $1 = file, $2 = dotted key (top.sub)
  local file="$1" key="$2"
  python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import sys, yaml
file, key = sys.argv[1], sys.argv[2]
try:
    with open(file) as f:
        data = yaml.safe_load(f) or {}
    cur = data
    for part in key.split('.'):
        cur = cur.get(part) if isinstance(cur, dict) else None
        if cur is None:
            sys.exit(0)
    print(cur if isinstance(cur, (str, int)) else "")
except Exception:
    sys.exit(0)
PY
}

PROJECT_NAME=""
AGENT_NAME=""
FOUNDRY_FQDN=""

for src in "$CAPS_FILE" "$AGENT_YAML"; do
  [[ -f "$src" ]] || continue
  [[ -z "$PROJECT_NAME" ]] && PROJECT_NAME=$(yaml_get "$src" "project_name")
  [[ -z "$AGENT_NAME" ]]   && AGENT_NAME=$(yaml_get "$src" "agent_name")
  [[ -z "$FOUNDRY_FQDN" ]] && {
    ACCT=$(yaml_get "$src" "foundry_account_name")
    [[ -n "$ACCT" ]] && FOUNDRY_FQDN="${ACCT}.services.ai.azure.com"
  }
done

# Last-resort: pull from agent-status deploy block if present.
[[ -z "$AGENT_NAME" ]] && AGENT_NAME=$(jq -r '.agent_name // ""' "$STATUS_FILE")
[[ -z "$FOUNDRY_FQDN" ]] && {
  EP=$(jq -r '.deploy.endpoint // ""' "$STATUS_FILE")
  # endpoint shape: https://<acct>.services.ai.azure.com/api/projects/<proj>
  if [[ -n "$EP" ]]; then
    FOUNDRY_FQDN=$(echo "$EP" | awk -F'/' '{print $3}')
    [[ -z "$PROJECT_NAME" ]] && PROJECT_NAME=$(echo "$EP" | awk -F'/projects/' '{print $2}' | awk -F'/' '{print $1}')
  fi
}

missing=()
[[ -z "$PROJECT_NAME" ]] && missing+=("project_name")
[[ -z "$AGENT_NAME" ]]   && missing+=("agent_name")
[[ -z "$FOUNDRY_FQDN" ]] && missing+=("foundry account fqdn")

if (( ${#missing[@]} > 0 )); then
  {
    echo "[x] --inline could not resolve: ${missing[*]}"
    echo "    Add them to agent-capabilities.yaml (project_name / agent_name / foundry_account_name)"
    echo "    OR fall back to placeholder mode (drop the --inline flag) and set"
    echo "    the named values in APIM after pasting."
  } >&2
  exit 4
fi

INLINED=$POLICY_XML
INLINED=${INLINED//\{\{bot-app-id\}\}/$BOT_APP_ID}
INLINED=${INLINED//\{\{foundry-account-fqdn\}\}/$FOUNDRY_FQDN}
INLINED=${INLINED//\{\{project-name\}\}/$PROJECT_NAME}
INLINED=${INLINED//\{\{agent-name\}\}/$AGENT_NAME}

printf '%s\n' "$INLINED"
