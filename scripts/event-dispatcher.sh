#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# event-dispatcher.sh — 事件分发器（Hermes cron script 模式）
#
# 设计思路（Loop Engineering）:
#   这是事件驱动架构的核心调度器。
#   它不是 Agent，而是决定"是否以及如何唤醒 Agent"的控制器。
#
# 职责:
#   1. 检查事件监听器是否存活（心跳检测）
#   2. 读取 events/ 目录中的新事件
#   3. 根据事件类型决定处理策略
#   4. 输出 Agent 指令包（或静默退出）
#
# 事件路由规则:
#   - 用户消息包含"报告"/"岗位"/"投递" → 触发反馈处理
#   - 用户消息包含"Y"/"N"/"A" + 数字 → 标记反馈
#   - reaction 事件（如 👍/👎）→ 补充反馈信号
#   - 无关消息 → 忽略
#
# 输出逻辑:
#   - 有相关事件 → 输出 Agent 指令包 → Agent 被唤醒
#   - 无事件 → 静默退出 → Agent 不触发
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

EVENTS_DIR="$JOB_WORKSPACE/events"
PROCESSED_DIR="$JOB_WORKSPACE/events/.processed"
PID_FILE="$JOB_WORKSPACE/.listener.pid"

mkdir -p "$EVENTS_DIR" "$PROCESSED_DIR"

log_event() {
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg type "$1" \
    --arg detail "$2" \
    '{timestamp: $ts, event: $type, detail: $detail}' >> "$JOB_AUDIT"
}

# ── 第 1 步: 心跳检测 ──
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  LISTENER_OK=true
else
  LISTENER_OK=false
  log_event "listener_down" "event listener not running, attempting restart"
  # 尝试自动重启
  bash "$JOB_SCRIPTS/event-listener.sh" start 2>/dev/null || true
fi

# ── 第 2 步: 收集新事件 ──
NEW_EVENTS=()
for f in "$EVENTS_DIR"/*.json; do
  [ -f "$f" ] || continue
  NEW_EVENTS+=("$f")
done

EVENT_COUNT=${#NEW_EVENTS[@]}

if [ "$EVENT_COUNT" -eq 0 ]; then
  log_event "dispatcher_tick" "no new events"
  exit 0
fi

log_event "events_found" "$EVENT_COUNT new events"

# ── 第 3 步: 事件分类与路由 ──
FEEDBACK_EVENTS=()      # 用户反馈（Y/N/A 标记）
REPORT_QUERY_EVENTS=()  # 用户询问报告
GENERAL_EVENTS=()       # 其他消息

for f in "${NEW_EVENTS[@]}"; do
  EVENT=$(cat "$f")
  EVENT_TYPE=$(echo "$EVENT" | jq -r '.event_type // ""')
  CONTENT=$(echo "$EVENT" | jq -r '.content // ""' | tr '[:upper:]' '[:lower:]')
  CHAT_ID=$(echo "$EVENT" | jq -r '.chat_id // ""')
  SENDER=$(echo "$EVENT" | jq -r '.sender_id // ""')
  
  # 路由判断
  if echo "$CONTENT" | grep -qE '^(y|n|a|yes|no)\s+[0-9]'; then
    # 反馈标记: "Y 1,3" / "N 2" / "A 5"
    FEEDBACK_EVENTS+=("$f")
  elif echo "$CONTENT" | grep -qE '报告|岗位|投递|简历|面试|看了|反馈'; then
    # 报告相关询问
    REPORT_QUERY_EVENTS+=("$f")
  elif echo "$CONTENT" | grep -qE '全部|all\s*y|all\s*n'; then
    # 全部标记
    FEEDBACK_EVENTS+=("$f")
  else
    GENERAL_EVENTS+=("$f")
  fi
  
  # 移动到已处理目录
  mv "$f" "$PROCESSED_DIR/" 2>/dev/null || true
done

# ── 第 4 步: 组装 Agent 指令包 ──
INSTRUCTION=""
HAS_ACTION=false

# 处理反馈事件
if [ ${#FEEDBACK_EVENTS[@]} -gt 0 ]; then
  HAS_ACTION=true
  INSTRUCTION+="📋 收到 ${#FEEDBACK_EVENTS[@]} 条用户反馈:\n\n"
  
  for f in "${FEEDBACK_EVENTS[@]}"; do
    CONTENT=$(jq -r '.content' "$f")
    SENDER=$(jq -r '.sender_id' "$f")
    INSTRUCTION+="  来自 $SENDER: $CONTENT\n"
  done
  
  INSTRUCTION+="\n请执行:\n"
  INSTRUCTION+="1. 加载 skill: job-hunter-feedback\n"
  INSTRUCTION+="2. 解析反馈标记（Y=感兴趣, N=不感兴趣, A=已投递）\n"
  INSTRUCTION+="3. 对 Y 标记的岗位生成投递方案\n"
  INSTRUCTION+="4. 更新 queue.jsonl 和 preferences.json\n"
  INSTRUCTION+="5. 通过飞书消息回复用户确认\n\n"
fi

# 处理报告查询事件
if [ ${#REPORT_QUERY_EVENTS[@]} -gt 0 ]; then
  HAS_ACTION=true
  INSTRUCTION+="💬 用户询问报告/岗位信息 (${#REPORT_QUERY_EVENTS[@]} 条):\n\n"
  
  for f in "${REPORT_QUERY_EVENTS[@]}"; do
    CONTENT=$(jq -r '.content' "$f")
    INSTRUCTION+="  消息: $CONTENT\n"
  done
  
  INSTRUCTION+="\n请执行:\n"
  INSTRUCTION+="1. 读取 queue.jsonl 获取最新报告状态\n"
  INSTRUCTION+="2. 读取报告内容（如有待处理报告）\n"
  INSTRUCTION+="3. 通过飞书消息回复用户\n\n"
fi

# 监听器状态提醒
if [ "$LISTENER_OK" = "false" ]; then
  INSTRUCTION+="⚠️ 事件监听器已掉线，已尝试自动重启。请检查: bash $JOB_SCRIPTS/event-listener.sh status\n\n"
fi

if [ "$HAS_ACTION" = "true" ]; then
  echo -e "$INSTRUCTION"
  log_event "dispatcher_trigger" "feedback=${#FEEDBACK_EVENTS[@]} queries=${#REPORT_QUERY_EVENTS[@]}"
fi
