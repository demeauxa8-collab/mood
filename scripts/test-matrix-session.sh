#!/usr/bin/env bash
# Live test of the deployed `matrix-session` Edge Function (contract: docs/BACKEND-PLAN.md §2).
#
# Prints the HTTP status and body of the call, then checks the returned Matrix session with
# GET /_matrix/client/v3/account/whoami. The Supabase token is never printed and never put on a
# command line (it reaches curl through stdin); the Matrix access token of the reply is masked.
#
# Usage:
#   scripts/test-matrix-session.sh <supabase_access_token>
#   scripts/test-matrix-session.sh - < token.txt      # keeps the token out of shell history and ps
#   MOOD_ACCESS_TOKEN=... scripts/test-matrix-session.sh
#
# Optional environment:
#   SUPABASE_URL       default https://jxpgyblzymshyzbkgmat.supabase.co
#   SUPABASE_ANON_KEY  public key sent as `apikey`; default: read from Config.xcconfig if present
#   MOOD_DEVICE_ID     default MOODTESTCLI00001 (reuse it: the same Matrix device is kept)
#   MOOD_DEVICE_NAME   default "Mood · test CLI"
#   REPEAT=1           call a second time: expects created=false, same user_id and device_id
set -euo pipefail
set +x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_URL="${SUPABASE_URL:-https://jxpgyblzymshyzbkgmat.supabase.co}"
SUPABASE_URL="${SUPABASE_URL%/}"
DEVICE_ID="${MOOD_DEVICE_ID:-MOODTESTCLI00001}"
DEVICE_NAME="${MOOD_DEVICE_NAME:-Mood · test CLI}"
FUNCTION_URL="$SUPABASE_URL/functions/v1/matrix-session"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

TOKEN="${1:-}"
if [[ "$TOKEN" == "-h" || "$TOKEN" == "--help" ]]; then usage; fi
if [[ "$TOKEN" == "-" ]]; then
  IFS= read -r TOKEN || true
fi
TOKEN="${TOKEN:-${MOOD_ACCESS_TOKEN:-}}"
TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
[[ -n "$TOKEN" ]] || usage

ANON_KEY="${SUPABASE_ANON_KEY:-}"
if [[ -z "$ANON_KEY" && -f "$ROOT_DIR/Config.xcconfig" ]]; then
  ANON_KEY="$(sed -nE 's/^[[:space:]]*SUPABASE_ANON_KEY[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$ROOT_DIR/Config.xcconfig" | head -n 1)"
fi
if [[ -z "$ANON_KEY" ]]; then
  echo "note: no SUPABASE_ANON_KEY found, calling without the apikey header" >&2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
json_string() { sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" <<<"$2" | head -n 1; }
json_bool() { sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" <<<"$2" | head -n 1; }
mask() { sed -E 's/("access_token"[[:space:]]*:[[:space:]]*")[^"]*"/\1<masked>"/g' <<<"$1"; }

PAYLOAD="{\"device_id\":\"$(json_escape "$DEVICE_ID")\",\"device_name\":\"$(json_escape "$DEVICE_NAME")\"}"

# Sets STATUS and BODY. Secrets travel in a curl config read from stdin, never in argv.
call_function() {
  local config
  config="header = \"Authorization: Bearer $TOKEN\""
  if [[ -n "$ANON_KEY" ]]; then config+=$'\n'"header = \"apikey: $ANON_KEY\""; fi
  STATUS="$(printf '%s\n' "$config" | curl -sS --max-time 40 -K - \
    -X POST -H "Content-Type: application/json" --data "$PAYLOAD" \
    -o "$TMP_DIR/body" -w '%{http_code}' "$FUNCTION_URL" || true)"
  BODY="$(cat "$TMP_DIR/body" 2>/dev/null || true)"
}

report() {
  echo "POST $FUNCTION_URL  (device_id=$DEVICE_ID)"
  echo "status: ${STATUS:-no response}"
  echo "body:   $(mask "$BODY")"
}

call_function
report
[[ "$STATUS" == "200" ]] || exit 1

HOMESERVER="$(json_string homeserver "$BODY")"
USER_ID="$(json_string user_id "$BODY")"
RETURNED_DEVICE="$(json_string device_id "$BODY")"
MATRIX_TOKEN="$(json_string access_token "$BODY")"
FIRST_CREATED="$(json_bool created "$BODY")"
[[ -n "$HOMESERVER" && -n "$USER_ID" && -n "$MATRIX_TOKEN" ]] || { echo "FAIL: reply misses contract fields" >&2; exit 1; }
[[ "$RETURNED_DEVICE" == "$DEVICE_ID" ]] || echo "WARN: device_id differs from the requested one" >&2

echo
echo "GET $HOMESERVER/_matrix/client/v3/account/whoami"
WHOAMI_STATUS="$(printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_TOKEN" | curl -sS --max-time 15 -K - \
  -o "$TMP_DIR/whoami" -w '%{http_code}' "$HOMESERVER/_matrix/client/v3/account/whoami" || true)"
WHOAMI="$(cat "$TMP_DIR/whoami" 2>/dev/null || true)"
echo "status: ${WHOAMI_STATUS:-no response}"
echo "body:   $WHOAMI"
[[ "$WHOAMI_STATUS" == "200" && "$(json_string user_id "$WHOAMI")" == "$USER_ID" ]] || { echo "FAIL: whoami does not confirm $USER_ID" >&2; exit 1; }

if [[ "${REPEAT:-0}" == "1" ]]; then
  echo
  call_function
  report
  [[ "$STATUS" == "200" ]] || exit 1
  [[ "$(json_bool created "$BODY")" == "false" ]] || { echo "FAIL: second call should have created=false" >&2; exit 1; }
  [[ "$(json_string user_id "$BODY")" == "$USER_ID" ]] || { echo "FAIL: user_id changed" >&2; exit 1; }
  [[ "$(json_string device_id "$BODY")" == "$RETURNED_DEVICE" ]] || { echo "FAIL: device_id changed" >&2; exit 1; }
fi

echo
echo "OK: $USER_ID on $HOMESERVER (first call created=$FIRST_CREATED)"
