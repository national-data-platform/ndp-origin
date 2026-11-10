#!/usr/bin/env bash
# Try the token exchange end to end (README step 7). Settings: exchange.env.
set -euo pipefail

set -a
source .env
set +a

KC="$KC_REALM_URL/protocol/openid-connect"
ORIGIN="${PELICAN_ORIGIN:-https://localhost:8444}"
TX=urn:ietf:params:oauth:grant-type:token-exchange
AT=urn:ietf:params:oauth:token-type:access_token

# token URL [curl args...]: POST, print the access token, or show the server's reply and stop.
token() {
  local reply
  reply=$(curl -sS "$@")
  jq -er .access_token <<<"$reply" 2>/dev/null || { echo "Request to $1 failed: $reply" >&2; exit 1; }
}
# claims TOKEN: a JWT's claims, for display.
claims() {
  jq -R 'split(".")[1] | gsub("-"; "+") | gsub("_"; "/") | . + ("=" * ((4 - length % 4) % 4)) | @base64d | fromjson' <<<"$1"
}

echo "1. Sign in to Keycloak"
device=$(curl -sS "$KC/auth/device" -d client_id="$KC_CLIENT_ID" \
  --data-urlencode client_secret="$KC_CLIENT_SECRET" -d scope=openid)
link=$(jq -er .verification_uri_complete <<<"$device" 2>/dev/null) || { echo "Device sign-in failed: $device" >&2; exit 1; }
echo "   Open $link"
read -rp "   and sign in through CILogon, then press Enter... "
user_token=$(token "$KC/token" -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
  -d client_id="$KC_CLIENT_ID" --data-urlencode client_secret="$KC_CLIENT_SECRET" \
  -d device_code="$(jq -r .device_code <<<"$device")")

echo "2. Keycloak retargets the token at Pelican"
kc_token=$(token "$KC/token" -d grant_type=$TX -d client_id="$KC_CLIENT_ID" \
  --data-urlencode client_secret="$KC_CLIENT_SECRET" -d subject_token="$user_token" \
  -d subject_token_type=$AT -d scope=pelican -d audience=pelican-origin)
claims "$kc_token" | jq '{aud, azp, upstream_sub, identity_provider}'

echo "3. The origin exchanges it for a Pelican token"
pelican_token=$(token "$ORIGIN/api/v1.0/issuer/ns/ndp/token" -u "$PELICAN_ID:$PELICAN_SECRET" \
  -d grant_type=$TX -d subject_token="$kc_token" -d subject_token_type=$AT \
  --data-urlencode "scope=openid storage.read:/")
claims "$pelican_token" | jq '{sub, scope, act}'

echo "4. Reading /ndp/climate/hello.txt with it"
curl -sS -H "Authorization: Bearer $pelican_token" "$ORIGIN/ndp/climate/hello.txt"