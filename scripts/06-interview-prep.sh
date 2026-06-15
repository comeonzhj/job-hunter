#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 06-interview-prep.sh — 面试准备触发器
#
# 扫描已投递岗位，生成 Agent 指令：公司背景、JD 拆解、预测问题、
# 简历经历映射和薪资谈判参考。
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

TASK_FILE="$JOB_WORKSPACE/interview-prep-tasks.jsonl"
touch "$TASK_FILE"

if [ ! -s "$JOB_QUEUE" ]; then
  exit 0
fi

PREP_JOBS=$(jq -s -c '
  [.[]
    | .batch_id as $batch_id
    | .jobs[]?
    | select((.pipeline_status // .feedback.status // "") == "applied")
    | select((.interview_prep_status // "") != "generated")
    | . + {batch_id: $batch_id}
  ]
' "$JOB_QUEUE")

COUNT=$(echo "$PREP_JOBS" | jq 'length')
[ "$COUNT" -eq 0 ] && exit 0

EXISTING_IDS=$(jq -s '[.[].security_id]' "$TASK_FILE" 2>/dev/null || echo "[]")
NEW_TASKS=$(jq -n --argjson jobs "$PREP_JOBS" --argjson existing "$EXISTING_IDS" '
  [$jobs[] | select(.security_id as $id | $existing | index($id) | not)]
')

NEW_COUNT=$(echo "$NEW_TASKS" | jq 'length')
[ "$NEW_COUNT" -eq 0 ] && exit 0

echo "$NEW_TASKS" | jq -c '.[] | {
  created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  security_id,
  batch_id,
  title: (.title // .job_name),
  company: (.company_name // .company),
  status: "pending"
}' >> "$TASK_FILE"

cat <<EOF
🎯 检测到 $NEW_COUNT 个已投递岗位需要面试准备

岗位:
$(echo "$NEW_TASKS" | jq -r '.[] | "  • \(.title // .job_name) @ \(.company_name // .company) | \(.salary_desc // .salary // "薪资未知")"')

请执行:
1. 读取 $JOB_CONFIG，尤其是简历参考
2. 对每个岗位补充 boss detail
3. 生成面试准备文档：公司背景、JD 拆解、预测问题、经历映射、薪资谈判参考
4. 通过飞书发送文档链接
5. 将对应岗位 interview_prep_status 更新为 generated
EOF
