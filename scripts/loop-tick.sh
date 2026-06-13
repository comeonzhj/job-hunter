#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# loop-tick.sh — 主控循环脚本（Hermes cron script 模式）
#
# 完整循环: 事件检测 → 搜索 → 差异检测 → 文档反馈检测 → 输出
#
# 设计原则（Loop Engineering）:
#   1. 事件驱动优先: 实时事件 > 定时轮询
#   2. 轻量感知层: 脚本负责数据收集，零 token 消耗
#   3. 条件唤醒: 只在有新数据时才触发 Agent
#   4. 静默退出: 无新数据 → 输出空 → Agent 不触发
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

log_event() {
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg type "$1" \
    --arg detail "$2" \
    '{timestamp: $ts, event: $type, detail: $detail}' >> "$JOB_AUDIT"
}

log_event "tick_start" "loop-tick.sh started"

# ── 第 1 步: 处理实时事件（事件驱动） ──
EVENT_OUTPUT=$(bash "$JOB_SCRIPTS/event-dispatcher.sh" 2>/dev/null || echo "")
HAS_EVENTS=false
if [ -n "$EVENT_OUTPUT" ]; then
  HAS_EVENTS=true
  log_event "events_processed" "event dispatcher produced output"
fi

# ── 第 2 步: 搜索新岗位（定时轮询） ──
SEARCH_OUTPUT=$(bash "$JOB_SCRIPTS/01-search.sh" 2>/dev/null || echo '{"ok":false}')
SEARCH_ERROR=""
NEW_COUNT=0

if echo "$SEARCH_OUTPUT" | jq -e '.ok != true' &>/dev/null; then
  SEARCH_ERROR=$(echo "$SEARCH_OUTPUT" | jq -r '.error // "unknown"')
  log_event "search_failed" "$SEARCH_ERROR"
else
  TOTAL=$(echo "$SEARCH_OUTPUT" | jq '.total // 0')
  log_event "search_done" "found $TOTAL jobs"
  
  DIFF_OUTPUT=$(echo "$SEARCH_OUTPUT" | bash "$JOB_SCRIPTS/02-diff.sh" 2>/dev/null || echo '{"ok":false}')
  
  if echo "$DIFF_OUTPUT" | jq -e '.ok == true' &>/dev/null; then
    NEW_COUNT=$(echo "$DIFF_OUTPUT" | jq '.new_count // 0')
    if [ "$NEW_COUNT" -gt 0 ]; then
      log_event "new_jobs_found" "$NEW_COUNT new jobs queued"
    fi
  fi
fi

# ── 第 3 步: 检测文档反馈（定时轮询兜底） ──
DOC_FEEDBACK=$(bash "$JOB_SCRIPTS/03-check-feedback.sh" 2>/dev/null || echo '{"ok":false}')
HAS_DOC_FEEDBACK="false"

if echo "$DOC_FEEDBACK" | jq -e '.ok == true and .event_count > 0' &>/dev/null; then
  HAS_DOC_FEEDBACK="true"
  FEEDBACK_EVENTS=$(echo "$DOC_FEEDBACK" | jq '.event_count')
  log_event "doc_feedback_detected" "$FEEDBACK_EVENTS batches with activity"
fi

# ── 第 4 步: 决定是否唤醒 Agent ──
if [ "$HAS_EVENTS" = "false" ] && [ "$NEW_COUNT" -eq 0 ] && [ "$HAS_DOC_FEEDBACK" = "false" ]; then
  if [ -n "$SEARCH_ERROR" ]; then
    echo "⚠️ 搜索失败: $SEARCH_ERROR | 请运行 boss login"
  fi
  log_event "tick_end" "silent: no events, no new jobs, no doc feedback"
  exit 0
fi

# ── 第 5 步: 组装 Agent 指令包 ──
INSTRUCTION=""

# 实时事件输出
if [ "$HAS_EVENTS" = "true" ]; then
  INSTRUCTION+="$EVENT_OUTPUT\n\n"
fi

# 搜索异常
if [ -n "$SEARCH_ERROR" ]; then
  INSTRUCTION+="⚠️ 岗位搜索异常: $SEARCH_ERROR\n\n"
fi

# 新岗位
if [ "$NEW_COUNT" -gt 0 ]; then
  BATCH_ID=$(echo "$DIFF_OUTPUT" | jq -r '.batch_id')
  JOB_LIST=$(echo "$DIFF_OUTPUT" | jq -r '.jobs[]? | "  • \(.title // .job_name) @ \(.company_name // .company) | \(.salary_desc // .salary) | \(.city_name // .city)"')
  
  INSTRUCTION+="🔔 发现 $NEW_COUNT 个新岗位（批次: $BATCH_ID）\n"
  INSTRUCTION+="岗位列表:\n$JOB_LIST\n\n"
  INSTRUCTION+="请执行:\n"
  INSTRUCTION+="1. 读取配置: cat $JOB_CONFIG\n"
  INSTRUCTION+="2. 读取队列: cat $JOB_QUEUE\n"
  INSTRUCTION+="3. 加载 skill: job-hunter-sop\n"
  INSTRUCTION+="4. 加载 skill: job-hunter-delivery\n"
  INSTRUCTION+="5. 对每个 pending 岗位执行 boss detail 获取详情\n"
  INSTRUCTION+="6. 6 维度评分 → 生成报告 → 飞书文档交付\n\n"
fi

# 文档反馈
if [ "$HAS_DOC_FEEDBACK" = "true" ]; then
  INSTRUCTION+="📋 检测到文档交互（checkbox/评论变化）\n"
  INSTRUCTION+="详情: $(echo "$DOC_FEEDBACK" | jq -c '.events')\n\n"
  INSTRUCTION+="请执行:\n"
  INSTRUCTION+="1. 加载 skill: job-hunter-feedback\n"
  INSTRUCTION+="2. 解析 checkbox 勾选和评论\n"
  INSTRUCTION+="3. 对标记感兴趣的岗位生成投递方案\n"
  INSTRUCTION+="4. 更新偏好模型: $JOB_PREFERENCES\n\n"
fi

echo -e "$INSTRUCTION"
log_event "tick_end" "agent triggered: events=$HAS_EVENTS new=$NEW_COUNT doc_feedback=$HAS_DOC_FEEDBACK"
