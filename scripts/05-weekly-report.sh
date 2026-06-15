#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 05-weekly-report.sh — 求职周报生成器
#
# 生成本地 Markdown 周报草稿，并输出 Agent 指令用于飞书交付。
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

WEEK_ID="$(date +%G-W%V)"
REPORT_PATH="$JOB_WORKSPACE/reports/weekly-$WEEK_ID.md"
MARKET_JSON="$(bash "$JOB_SCRIPTS/04-market-intel.sh" 30)"

QUEUE_STATS=$(jq -s '{
  batches: length,
  pending: ([.[] | select(.status == "pending")] | length),
  waiting_feedback: ([.[] | select(.status == "waiting_feedback")] | length),
  archived: ([.[] | select(.status == "auto_archived" or .status == "archived")] | length),
  applied: ([.[] | select((.jobs[]?.pipeline_status // "") == "applied")] | length),
  job_count: ([.[] | .job_count // (.jobs | length)] | add // 0)
}' "$JOB_QUEUE" 2>/dev/null || echo '{"batches":0,"pending":0,"waiting_feedback":0,"archived":0,"applied":0,"job_count":0}')

SIGNALS=$(jq -r '.signals_received // 0' "$JOB_PREFERENCES" 2>/dev/null || echo "0")
MATURITY=$(jq -n --argjson signals "$SIGNALS" 'if $signals < 10 then "冷启动" elif $signals < 50 then "学习期" elif $signals < 100 then "稳定期" else "自适应期" end' | tr -d '"')

cat > "$REPORT_PATH" <<EOF
# 求职周报 — $WEEK_ID

## 本周概览

- 累计发现岗位：$(echo "$QUEUE_STATS" | jq -r '.job_count') 个
- 待处理批次：$(echo "$QUEUE_STATS" | jq -r '.pending') 个
- 等待反馈批次：$(echo "$QUEUE_STATS" | jq -r '.waiting_feedback') 个
- 自动归档批次：$(echo "$QUEUE_STATS" | jq -r '.archived') 个
- 偏好模型阶段：${MATURITY}（信号数：${SIGNALS}）

## 市场情报

- 样本岗位：$(echo "$MARKET_JSON" | jq -r '.total_jobs // 0') 个
- 活跃公司数：$(echo "$MARKET_JSON" | jq -r '.unique_companies // 0') 个
- 平均薪资中位估算：$(echo "$MARKET_JSON" | jq -r '.salary.avg_k // "未知"')K

### 活跃公司 Top 5

$(echo "$MARKET_JSON" | jq -r '.active_companies[:5][]? | "- \(.company)：\(.count) 个岗位"')

### 热门技能 Top 8

$(echo "$MARKET_JSON" | jq -r '.hot_skills[:8][]? | "- \(.key)：\(.count) 次"')

## 下周建议

- 优先处理等待反馈的报告，避免好岗位过期。
- 对高频技能补充简历证据，尤其是市场情报中持续升温的关键词。
- 如果连续多批无感兴趣岗位，调整关键词或排除规则。
EOF

jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg type "weekly_report_generated" \
  --arg detail "$REPORT_PATH" \
  '{timestamp: $ts, event: $type, detail: $detail}' >> "$JOB_AUDIT"

cat <<EOF
📊 已生成求职周报草稿: $REPORT_PATH

请执行:
1. 读取周报草稿
2. 加载 job-hunter-delivery skill
3. 将周报发布为飞书文档或发送摘要消息
4. 把文档链接记录到审计日志
EOF
