#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 09-kanban-sync.sh — 求职进度看板同步
#
# 生成本地 CSV 看板；如配置了 Feishu Base，输出 Agent 同步指令。
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

KANBAN_CSV="$JOB_WORKSPACE/kanban.csv"
BASE_APP_TOKEN=$(jq -r '.delivery.feishu_base_app_token // ""' "$JOB_CONFIG")
BASE_TABLE_ID=$(jq -r '.delivery.feishu_base_table_id // ""' "$JOB_CONFIG")

{
  echo "batch_id,security_id,company,title,salary,city,status,doc_url,updated_at"
  if [ -s "$JOB_QUEUE" ]; then
    jq -r --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" -s '
      .[]
      | .batch_id as $batch_id
      | (.doc_url // "") as $doc_url
      | .jobs[]?
      | [
          $batch_id,
          (.security_id // ""),
          (.company_name // .company // ""),
          (.title // .job_name // ""),
          (.salary_desc // .salary // ""),
          (.city_name // .city // ""),
          (.pipeline_status // "new_found"),
          $doc_url,
          $now
        ]
      | @csv
    ' "$JOB_QUEUE"
  fi
} > "$KANBAN_CSV"

jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg type "kanban_synced" \
  --arg detail "$KANBAN_CSV" \
  '{timestamp: $ts, event: $type, detail: $detail}' >> "$JOB_AUDIT"

if [ -n "$BASE_APP_TOKEN" ] && [ -n "$BASE_TABLE_ID" ]; then
  cat <<EOF
📌 求职看板 CSV 已更新: $KANBAN_CSV

检测到飞书 Base 配置，请执行:
1. 读取 $KANBAN_CSV
2. 将记录同步到 Base app_token=$BASE_APP_TOKEN table_id=$BASE_TABLE_ID
3. 按 security_id 去重更新状态
EOF
else
  echo "📌 求职看板已更新: $KANBAN_CSV"
fi
