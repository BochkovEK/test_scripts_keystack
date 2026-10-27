#!/usr/bin/env bash
# Usage: ./update_vault_secret_accounts.sh <deployment> [passwords.txt]
# With no file, paste the lines and finish with Ctrl+D.
# Required: VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID; curl and jq.
# Optional: VAULT_CACERT, VAULT_SKIP_VERIFY=1, VAULT_KV_MOUNT (default secret_v2).
set -Eeuo pipefail
umask 077
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || die "Usage: $0 <deployment> [passwords.txt]"
deployment=$1
[[ "$deployment" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'Invalid deployment name'
: "${VAULT_ADDR:?VAULT_ADDR is required}" "${VAULT_ROLE_ID:?VAULT_ROLE_ID is required}" "${VAULT_SECRET_ID:?VAULT_SECRET_ID is required}"
command -v curl >/dev/null || die 'curl is required'
command -v jq >/dev/null || die 'jq is required'
mount=${VAULT_KV_MOUNT:-secret_v2}
[[ "$mount" =~ ^[A-Za-z0-9_-]+$ ]] || die 'Invalid KV mount'
base=${VAULT_ADDR%/}
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
curl_args=(--silent --show-error --connect-timeout 10 --max-time 60)
if [[ ${VAULT_SKIP_VERIFY:-0} == 1 ]]; then curl_args+=(--insecure); fi
if [[ -n ${VAULT_CACERT:-} ]]; then curl_args+=(--cacert "$VAULT_CACERT"); fi
if [[ $# == 2 ]]; then
  [[ -f "$2" && -r "$2" ]] || die 'Cannot read input file'
  input=$2
else
  printf 'Paste password lines, then press Ctrl+D:\n' >&2
  input=$tmpdir/input
  cp /dev/stdin "$input"
fi

# Reject unknown/duplicate labels and missing values before contacting Vault.
declare -A mapping=(
  ['LCM Gitlab root password']='gitlab_root_password'
  ['LCM Gitlab ks-admin password']='gitlab_ks_admin_password'
  ['LCM Grafana admin password']='grafana_admin_password'
  ['LCM Nexus admin password']='nexus_admin_password'
  ['LCM Netbox admin password']='netbox_admin_password'
  ['LCM Netbox ks-admin password']='netbox_ks_admin_password'
)
declare -A seen=()
printf '{}' > "$tmpdir/updates.json"
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" == *:* ]] || die 'Invalid line: missing colon'
  label=${line%%:*}
  value=${line#*:}
  label="${label%"${label##*[![:space:]]}"}"
  value="${value#"${value%%[![:space:]]*}"}"
  field=${mapping[$label]:-}
  [[ -n "$field" ]] || die "Unknown label: $label"
  [[ -n "$value" ]] || die "Empty password for: $label"
  [[ -z ${seen[$field]+x} ]] || die "Duplicate label: $label"
  seen[$field]=1
  # Pass values through stdin/environment rather than process arguments.
  VALUE="$value" FIELD="$field" jq '. + {(env.FIELD): env.VALUE}' "$tmpdir/updates.json" > "$tmpdir/next.json"
  mv "$tmpdir/next.json" "$tmpdir/updates.json"
done < "$input"
(( ${#seen[@]} > 0 )) || die 'No passwords supplied'

status=$(curl "${curl_args[@]}" -o "$tmpdir/health" -w '%{http_code}' "$base/v1/sys/health") || die 'Vault connection failed'
[[ $status == 200 ]] || die "Vault health returned HTTP $status"
ROLE="$VAULT_ROLE_ID" SECRET="$VAULT_SECRET_ID" jq -n '{role_id:env.ROLE,secret_id:env.SECRET}' > "$tmpdir/login.json"
status=$(curl "${curl_args[@]}" -X POST -H 'Content-Type: application/json' --data-binary "@$tmpdir/login.json" -o "$tmpdir/login-response" -w '%{http_code}' "$base/v1/auth/approle/login") || die 'AppRole login request failed'
[[ $status == 200 ]] || die "AppRole login failed: HTTP $status"
jq -er '"X-Vault-Token: " + .auth.client_token' "$tmpdir/login-response" > "$tmpdir/header" || die 'Missing client token'
url="$base/v1/$mount/data/deployments/$deployment/secrets/accounts"
status=$(curl "${curl_args[@]}" -H "@$tmpdir/header" -o "$tmpdir/current.json" -w '%{http_code}' "$url") || die 'Reading accounts failed'
[[ $status == 200 ]] || die "Cannot read existing accounts: HTTP $status; no changes made"
jq -e '.data.data | type == "object"' "$tmpdir/current.json" >/dev/null || die 'Invalid accounts response'
version=$(jq -er '.data.metadata.version | select(type == "number" and . > 0)' "$tmpdir/current.json") || die 'Missing KV version'
jq -n --slurpfile current "$tmpdir/current.json" --slurpfile updates "$tmpdir/updates.json" --argjson version "$version" '{options:{cas:$version},data:($current[0].data.data + $updates[0])}' > "$tmpdir/write.json"
printf '\nVault: %s\nPath: %s/deployments/%s/secrets/accounts\nFields to update:\n' "$base" "$mount" "$deployment"
jq -r 'keys[] | "  " + .' "$tmpdir/updates.json"
printf 'Existing values in other fields are preserved. Press Enter to write, or Ctrl+C to cancel: '
IFS= read -r confirmation || die 'No confirmation received'
[[ -z "$confirmation" ]] || die 'Cancelled: confirmation must be empty'
status=$(curl "${curl_args[@]}" -X POST -H "@$tmpdir/header" -H 'Content-Type: application/json' --data-binary "@$tmpdir/write.json" -o "$tmpdir/write-response" -w '%{http_code}' "$url") || die 'Write request failed; check Vault before retrying'
[[ $status == 200 ]] || die "Write failed: HTTP $status (possibly version conflict; rerun to refresh)"
printf 'Accounts updated; KV version: %s\n' "$(jq -r '.data.version // "unknown"' "$tmpdir/write-response")"
