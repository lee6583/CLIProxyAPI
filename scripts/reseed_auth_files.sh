#!/usr/bin/env bash
set -euo pipefail

# Reseed auth json files into CLIProxyAPI management API.
# Usage:
#   ./scripts/reseed_auth_files.sh \
#     --base-url https://cliproxyapi-hbg5.onrender.com \
#     --management-key <key> \
#     --source-dir /path/to/codex_tokens

BASE_URL=""
MGMT_KEY=""
SOURCE_DIR=""
ONLY_WHEN_EMPTY="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --management-key)
      MGMT_KEY="${2:-}"
      shift 2
      ;;
    --source-dir)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --always)
      ONLY_WHEN_EMPTY="false"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BASE_URL" || -z "$MGMT_KEY" || -z "$SOURCE_DIR" ]]; then
  echo "Missing required args." >&2
  echo "Example: ./scripts/reseed_auth_files.sh --base-url https://xxx.onrender.com --management-key xxx --source-dir ../chatgpt_register/codex_tokens" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

AUTH_LIST_URL="${BASE_URL%/}/v0/management/auth-files?is_webui=1"
UPLOAD_URL="${BASE_URL%/}/v0/management/auth-files"

if [[ "$ONLY_WHEN_EMPTY" == "true" ]]; then
  current_count=$(curl -sS -H "Authorization: Bearer $MGMT_KEY" "$AUTH_LIST_URL" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(len(data.get("files",[])))')
  echo "Remote auth file count: $current_count"
  if [[ "$current_count" != "0" ]]; then
    echo "Skip reseed because remote is not empty. Use --always to force upload."
    exit 0
  fi
fi

total=0
ok=0
fail=0

while IFS= read -r -d '' file; do
  total=$((total+1))
  code=$(curl -sS -o /tmp/cpa_reseed_resp.json -w "%{http_code}" \
    -H "Authorization: Bearer $MGMT_KEY" \
    -F "file=@${file};type=application/json" \
    "$UPLOAD_URL" || true)
  if [[ "$code" == "200" ]]; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
    echo "Upload failed [$code]: $(basename "$file")"
  fi

done < <(find "$SOURCE_DIR" -type f \( -name '*.json' -o -name '*.JSON' \) -print0)

echo "Reseed finished: total=$total ok=$ok fail=$fail"

new_count=$(curl -sS -H "Authorization: Bearer $MGMT_KEY" "$AUTH_LIST_URL" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(len(data.get("files",[])))')
echo "Remote auth file count after reseed: $new_count"

if [[ "$fail" -gt 0 ]]; then
  exit 2
fi
