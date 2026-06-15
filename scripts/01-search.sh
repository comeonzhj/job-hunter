#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 01-search.sh — 调用 boss-agent-cli 搜索岗位
# 输出: JSON 格式的搜索结果到 stdout
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

# 读取配置
CITY=$(jq -r '.user.city' "$JOB_CONFIG")
WELFARE=$(jq -r '.user.welfare | join(",")' "$JOB_CONFIG")
SALARY_MIN=$(jq -r '.user.salary_min // empty' "$JOB_CONFIG")
SALARY_MAX=$(jq -r '.user.salary_max // empty' "$JOB_CONFIG")
EXPERIENCE=$(jq -r '.user.experience // empty' "$JOB_CONFIG")
PLATFORM=$(jq -r '.user.platform // "zhipin"' "$JOB_CONFIG")
KEYWORDS=()
while IFS= read -r item; do
  [ -n "$item" ] && KEYWORDS+=("$item")
done < <(jq -r '.user.keywords[]' "$JOB_CONFIG")

EXCLUDE_KEYWORDS=()
while IFS= read -r item; do
  [ -n "$item" ] && EXCLUDE_KEYWORDS+=("$item")
done < <(jq -r '.user.exclude_keywords[]?' "$JOB_CONFIG")
SALARY=""
[ -n "$SALARY_MIN" ] && [ -n "$SALARY_MAX" ] && SALARY="${SALARY_MIN}-${SALARY_MAX}K"

echo "🔍 搜索岗位: platform=$PLATFORM city=$CITY keywords=\"${KEYWORDS[*]}\" welfare=\"$WELFARE\"" >&2

if ! command -v boss &>/dev/null; then
  echo '{"ok":false,"error":"boss-agent-cli not installed","hint":"uv tool install boss-agent-cli"}'
  exit 1
fi

STATUS=$(boss --platform "$PLATFORM" --json status 2>/dev/null || echo '{"ok":false}')
if echo "$STATUS" | jq -e '.ok != true' &>/dev/null; then
  HINT=$(echo "$STATUS" | jq -r '.error.recovery_action // "boss --platform '"$PLATFORM"' login"' | awk 'NF {print; exit}')
  echo '{"ok":false,"error":"not logged in","hint":"'"$HINT"'"}'
  exit 1
fi

RESULTS="[]"
for KW in "${KEYWORDS[@]}"; do
  SEARCH_CMD=(boss --platform "$PLATFORM" --json search "$KW" --city "$CITY")
  [ -n "$WELFARE" ] && SEARCH_CMD+=(--welfare "$WELFARE")
  [ -n "$SALARY" ] && SEARCH_CMD+=(--salary "$SALARY")
  [ -n "$EXPERIENCE" ] && SEARCH_CMD+=(--experience "$EXPERIENCE")

  SEARCH_RESULT=$("${SEARCH_CMD[@]}" \
    2>/dev/null || echo '{"ok":false,"data":[]}')
  
  if echo "$SEARCH_RESULT" | jq -e '.ok == true' &>/dev/null; then
    ITEMS=$(echo "$SEARCH_RESULT" | jq 'if (.data | type) == "array" then .data else (.data.items // .data.jobs // .data.results // []) end')
    RESULTS=$(echo "$RESULTS" "$ITEMS" | jq -s '.[0] + .[1]')
  fi
  sleep 2
done

EXCLUDE_JSON=$(printf '%s\n' "${EXCLUDE_KEYWORDS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')
RESULTS=$(jq -n --argjson jobs "$RESULTS" --argjson excludes "$EXCLUDE_JSON" '
  $jobs
  | map(select(
      . as $job |
      (($job.title // $job.job_name // "") + " " + ($job.company_name // $job.company // "") + " " + ($job.job_desc // $job.description // "")) as $text |
      all($excludes[]?; ($text | contains(.)) | not)
    ))
  | unique_by(.security_id // (.title // .job_name // "") + "|" + (.company_name // .company // ""))
')

echo "$RESULTS" | jq '{
  ok: true,
  timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  city: "'"$CITY"'",
  total: (. | length),
  jobs: .
}'
