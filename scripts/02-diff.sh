#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 02-diff.sh — 差异检测：识别新增岗位
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${JOB_HOME:-}" ] && [ -f "$JOB_HOME/scripts/env.sh" ]; then
  source "$JOB_HOME/scripts/env.sh"
elif [ -f "$SCRIPT_DIR/env.sh" ]; then
  source "$SCRIPT_DIR/env.sh"
else
  source "$HOME/.hermes/job-hunter/scripts/env.sh"
fi

# 读取搜索结果
if [ -t 0 ]; then
  SEARCH_INPUT=$(cat "$1")
else
  SEARCH_INPUT=$(cat)
fi

if ! echo "$SEARCH_INPUT" | jq -e '.ok == true' &>/dev/null; then
  echo '{"ok":false,"error":"invalid search input","new_jobs":[]}'
  exit 1
fi

ALL_JOBS=$(echo "$SEARCH_INPUT" | jq '.jobs // []')

SEEN_IDS="[]"
if [ -s "$JOB_SEEN" ]; then
  SEEN_IDS=$(jq -s '[.[].security_id]' "$JOB_SEEN")
fi

NEW_JOBS=$(jq -n --argjson jobs "$ALL_JOBS" --argjson seen "$SEEN_IDS" '
  [$jobs[] | select(.security_id as $sid | $seen | index($sid) | not)]
')

NEW_COUNT=$(echo "$NEW_JOBS" | jq 'length')

if [ "$NEW_COUNT" -eq 0 ]; then
  echo '{"ok":true,"new_count":0,"new_jobs":[],"message":"无新增岗位"}'
  exit 0
fi

BATCH_ID="batch_$(date +%Y%m%d_%H%M%S)"
OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "$NEW_JOBS" | jq -c --arg observed_at "$OBSERVED_AT" --arg batch_id "$BATCH_ID" \
  '.[] | . + {observed_at: $observed_at, batch_id: $batch_id}' >> "$JOB_SEEN"

QUEUE_ENTRY=$(jq -cn \
  --arg batch_id "$BATCH_ID" \
  --arg timestamp "$OBSERVED_AT" \
  --argjson jobs "$NEW_JOBS" \
  '{
    batch_id: $batch_id,
    timestamp: $timestamp,
    status: "pending",
    job_count: ($jobs | length),
    jobs: $jobs,
    feedback: null,
    report_path: null,
    doc_token: null,
    doc_url: null
  }')

echo "$QUEUE_ENTRY" >> "$JOB_QUEUE"

echo "$NEW_JOBS" | jq '{
  ok: true,
  new_count: length,
  batch_id: "'"$BATCH_ID"'",
  new_jobs: [.[] | {
    security_id,
    title: (.title // .job_name // "未知"),
    company: (.company_name // .company // "未知"),
    salary: (.salary_desc // .salary // "面议"),
    city: (.city_name // .city // ""),
    benefits: (.welfare_list // .benefits // [])
  }],
  message: ("发现 " + (length | tostring) + " 个新岗位，已加入处理队列")
}'
