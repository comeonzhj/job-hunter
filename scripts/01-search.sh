#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 01-search.sh — 调用 boss-agent-cli 搜索岗位
# 输出: JSON 格式的搜索结果到 stdout
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# 读取配置
CITY=$(jq -r '.user.city' "$JOB_CONFIG")
KEYWORDS=$(jq -r '.user.keywords | join(" ")' "$JOB_CONFIG")
WELFARE=$(jq -r '.user.welfare | join(",")' "$JOB_CONFIG")
COUNT=$(jq -r '.boss_cli.search_count // 30' "$JOB_CONFIG")
PLATFORM=$(jq -r '.user.platform // "zhipin"' "$JOB_CONFIG")

echo "🔍 搜索岗位: city=$CITY keywords=\"$KEYWORDS\" welfare=\"$WELFARE\" count=$COUNT" >&2

if ! command -v boss &>/dev/null; then
  echo '{"ok":false,"error":"boss-agent-cli not installed","hint":"uv tool install boss-agent-cli"}'
  exit 1
fi

STATUS=$(boss status --format json 2>/dev/null || echo '{"ok":false}')
if echo "$STATUS" | jq -e '.ok == false' &>/dev/null; then
  echo '{"ok":false,"error":"not logged in","hint":"boss login required"}'
  exit 1
fi

RESULTS="[]"
for KW in $KEYWORDS; do
  SEARCH_RESULT=$(boss search "$KW" \
    --city "$CITY" \
    --welfare "$WELFARE" \
    --count "$COUNT" \
    --platform "$PLATFORM" \
    --format json 2>/dev/null || echo '{"ok":false,"data":[]}')
  
  if echo "$SEARCH_RESULT" | jq -e '.ok == true' &>/dev/null; then
    ITEMS=$(echo "$SEARCH_RESULT" | jq '.data // []')
    RESULTS=$(echo "$RESULTS" "$ITEMS" | jq -s '.[0] + .[1]')
  fi
  sleep 2
done

RESULTS=$(echo "$RESULTS" | jq 'unique_by(.security_id)')

echo "$RESULTS" | jq '{
  ok: true,
  timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  city: "'"$CITY"'",
  total: (. | length),
  jobs: .
}'
