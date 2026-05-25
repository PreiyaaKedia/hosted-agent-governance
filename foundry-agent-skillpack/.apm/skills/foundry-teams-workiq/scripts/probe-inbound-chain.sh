#!/usr/bin/env bash
# Verification probe for the Teams / M365 Copilot → private Foundry inbound chain.
# Three probes — TLS, missing-auth 401, synthetic-invalid-JWT 401.
# All three MUST pass before the inbound chain is declared healthy.
#
# Tracked: TD-23.
#
# Usage:
#   probe-inbound-chain.sh <agent_path> <custom_domain> [--stamp]
#
#   <agent_path>     Path to the agent folder containing agent-status.json
#   <custom_domain>  The APIM custom domain (e.g. bot.contoso.com).
#                    The Bot Service messaging endpoint should be
#                    https://<custom_domain>/messages.
#   --stamp          When all three probes pass, write the inbound_chain block
#                    into agent-status.json. Default: print verdict only.
#
# Exit codes:
#   0  all three probes passed
#   1  one or more probes failed (verdict on stderr)
#   2  missing input files / args
#   3  missing required tools
#
# Read-only probes (a HEAD + two unauthenticated POSTs). The synthetic JWT is
# garbage by construction — there is no token reuse risk.

set -euo pipefail

AGENT_PATH="${1:?usage: probe-inbound-chain.sh <agent_path> <custom_domain> [--stamp]}"
CUSTOM_DOMAIN="${2:?usage: probe-inbound-chain.sh <agent_path> <custom_domain> [--stamp]}"
STAMP_MODE="${3:-}"

STATUS_FILE="$AGENT_PATH/agent-status.json"
if [[ ! -f "$STATUS_FILE" ]]; then
  echo "[x] $STATUS_FILE not found." >&2
  exit 2
fi

command -v curl >/dev/null 2>&1 || { echo "[x] missing: curl" >&2; exit 3; }
command -v jq   >/dev/null 2>&1 || { echo "[x] missing: jq"   >&2; exit 3; }

ENDPOINT="https://${CUSTOM_DOMAIN}/messages"

echo "[*] Probing $ENDPOINT" >&2

# ─── Probe 1: TLS smoke ───────────────────────────────────────────────────────
# curl exits non-zero if cert chain fails to validate against the system trust
# store. We deliberately do NOT pass -k — a cert problem here is the failure mode.

echo "[*] Probe 1/3 — TLS handshake + cert chain…" >&2
P1_OK=false
P1_DETAIL=""
if TLS_OUT=$(curl -sS -o /dev/null -w "HTTP=%{http_code} EXIT=0\n" -I "$ENDPOINT" 2>&1); then
  P1_OK=true
  P1_DETAIL="$(echo "$TLS_OUT" | tr -d '\n')"
else
  P1_DETAIL="curl failed: $(echo "$TLS_OUT" | head -1)"
fi

# ─── Probe 2: missing Authorization → 401 ─────────────────────────────────────

echo "[*] Probe 2/3 — POST without Authorization (expect 401)…" >&2
P2_OK=false
P2_DETAIL=""
P2_CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "$ENDPOINT" \
  -H 'Content-Type: application/json' \
  -d '{"type":"message","text":"probe"}' || echo "000")

if [[ "$P2_CODE" == "401" ]]; then
  P2_OK=true
  P2_DETAIL="401 as expected"
else
  P2_DETAIL="got $P2_CODE — expected 401. Policy may not be attached, or wrong API path."
fi

# ─── Probe 3: synthetic invalid JWT → 401 ─────────────────────────────────────
# A garbage three-segment string that looks like a JWT but cannot validate.
# The point is to confirm validate-jwt actually parses & rejects, not just
# bounce on missing header (which a non-jwt policy could also do).

SYNTH_JWT='eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJodHRwczovL2FwaS5ib3RmcmFtZXdvcmsuY29tIiwiYXVkIjoiZmFrZS1ib3QtaWQiLCJleHAiOjE2MDAwMDAwMDB9.aW52YWxpZC1zaWduYXR1cmU'

echo "[*] Probe 3/3 — POST with synthetic invalid JWT (expect 401)…" >&2
P3_OK=false
P3_DETAIL=""
P3_CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "$ENDPOINT" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $SYNTH_JWT" \
  -d '{"type":"message","text":"probe"}' || echo "000")

if [[ "$P3_CODE" == "401" ]]; then
  P3_OK=true
  P3_DETAIL="401 as expected (signature / issuer / audience rejected)"
else
  P3_DETAIL="got $P3_CODE — expected 401. validate-jwt may not be evaluating the token (passthrough)."
fi

# ─── Verdict ─────────────────────────────────────────────────────────────────

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat <<EOF
PROBE_TLS_OK=$P1_OK
PROBE_TLS_DETAIL=$P1_DETAIL
PROBE_MISSING_AUTH_OK=$P2_OK
PROBE_MISSING_AUTH_HTTP=$P2_CODE
PROBE_MISSING_AUTH_DETAIL=$P2_DETAIL
PROBE_INVALID_JWT_OK=$P3_OK
PROBE_INVALID_JWT_HTTP=$P3_CODE
PROBE_INVALID_JWT_DETAIL=$P3_DETAIL
PROBE_RAN_AT=$NOW
EOF

if [[ "$P1_OK" == "true" && "$P2_OK" == "true" && "$P3_OK" == "true" ]]; then
  echo "[+] Inbound chain healthy — all 3 probes passed." >&2
  PROBE_VERDICT=pass
else
  {
    echo "[x] Inbound chain UNHEALTHY:"
    [[ "$P1_OK" != "true" ]] && echo "    Probe 1 (TLS):           $P1_DETAIL"
    [[ "$P2_OK" != "true" ]] && echo "    Probe 2 (missing auth):  $P2_DETAIL"
    [[ "$P3_OK" != "true" ]] && echo "    Probe 3 (invalid JWT):   $P3_DETAIL"
    echo "    See inbound-firewall.md § Failure-mode lookup."
  } >&2
  PROBE_VERDICT=fail
fi

# ─── Optional: stamp agent-status.json on full pass ──────────────────────────

if [[ "$STAMP_MODE" == "--stamp" && "$PROBE_VERDICT" == "pass" ]]; then
  HELPER=".agents/skills/foundry-deploy/scripts/agent_status.py"
  if [[ ! -x "$HELPER" && ! -f "$HELPER" ]]; then
    echo "[!] --stamp requested but $HELPER not found in CWD; skipping stamp." >&2
  else
    BACKEND_URL=$(jq -r '
      .publish.inbound_chain.backend_url //
      ("https://" + (.deploy.endpoint // "" | sub("^https://";"")) + "/agents/" + (.agent_name // "") + "/endpoint/protocols/activityprotocol")
    ' "$STATUS_FILE")

    python3 "$HELPER" update \
      --agent-path "$AGENT_PATH" \
      --path 'publish.inbound_chain' \
      --json "{
        \"custom_fqdn\":\"$CUSTOM_DOMAIN\",
        \"backend_url\":\"$BACKEND_URL\",
        \"probe_at\":\"$NOW\",
        \"probe_verdict\":\"pass\"
      }" >/dev/null
    echo "[+] Stamped publish.inbound_chain in $STATUS_FILE" >&2
  fi
fi

[[ "$PROBE_VERDICT" == "pass" ]] || exit 1
