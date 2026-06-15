#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# event-listener.sh — 飞书事件实时监听器（常驻后台进程）
#
# Loop Engineering 核心组件：事件驱动触发器
# 
# 设计:
#   1. 通过 WebSocket 订阅飞书事件（im.message.receive_v1 等）
#   2. 事件写入 $JOB_WORKSPACE/events/ 目录（一个事件一个文件）
#   3. 重要事件触发 Hermes Agent（通过 hermes wake 或消息路由）
#
# 运行方式:
#   启动: bash event-listener.sh start
#   停止: bash event-listener.sh stop
#   状态: bash event-listener.sh status
#   重启: bash event-listener.sh restart
#
# 与 Agent 的关系:
#   本脚本是"常驻进程"，负责感知层。
#   Agent 是"被动响应"，由本脚本在检测到关键事件时唤醒。
#   这正是 Loop Engineering 的"循环控制器"角色。
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

EVENTS_DIR="$JOB_WORKSPACE/events"
PROCESSED_DIR="$JOB_WORKSPACE/events/.processed"
PID_FILE="$JOB_WORKSPACE/.listener.pid"
LOG_FILE="$JOB_WORKSPACE/event-listener.log"

mkdir -p "$EVENTS_DIR" "$PROCESSED_DIR"

# ── 命令分发 ──
case "${1:-start}" in
  start)
    # 检查是否已在运行
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "⚠️ Listener 已在运行 (PID: $(cat "$PID_FILE"))"
      exit 0
    fi

    echo "🎧 启动飞书事件监听器..."
    echo "   事件目录: $EVENTS_DIR"
    echo "   日志文件: $LOG_FILE"
    echo ""

    # 启动事件订阅（后台运行），每行事件落成一个 JSON 文件供 dispatcher 消费。
    nohup bash -c '
      set -euo pipefail
      lark-cli event +subscribe \
        --event-types "im.message.receive_v1,im.message.reaction.created_v1" \
        --compact \
        --jq '"'"'{
          event_type: .event_type,
          timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
          chat_id: .event.chat_id,
          sender_id: .event.sender_id,
          message_id: .event.message_id,
          message_type: .event.message_type,
          content: (if .event.message_type == "text" then (.event.content | fromjson | .text // .content // "") else .event.content end),
          reaction_type: .event.reaction_type
        }'"'"' \
      | while IFS= read -r event_line; do
          [ -n "$event_line" ] || continue
          event_file="'"$EVENTS_DIR"'/event_$(date +%s)_$RANDOM.json"
          printf "%s\n" "$event_line" > "$event_file"
        done
    ' >> "$LOG_FILE" 2>&1 &
    
    LISTENER_PID=$!
    echo "$LISTENER_PID" > "$PID_FILE"
    
    echo "✅ Listener 已启动 (PID: $LISTENER_PID)"
    echo ""
    echo "事件将写入: $EVENTS_DIR/"
    echo "日志: tail -f $LOG_FILE"
    ;;

  stop)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        echo "✅ Listener 已停止 (PID: $PID)"
      else
        echo "⚠️ 进程 $PID 已不存在"
      fi
      rm -f "$PID_FILE"
    else
      echo "⚠️ 未找到 PID 文件"
    fi
    ;;

  status)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      PID=$(cat "$PID_FILE")
      echo "✅ Listener 运行中 (PID: $PID)"
      echo "   启动时间: $(ps -o lstart= -p "$PID" 2>/dev/null || echo 'unknown')"
      echo "   事件目录: $EVENTS_DIR"
      echo "   待处理事件: $(ls "$EVENTS_DIR"/*.json 2>/dev/null | wc -l)"
      echo "   已处理事件: $(ls "$PROCESSED_DIR"/*.json 2>/dev/null | wc -l)"
    else
      echo "❌ Listener 未运行"
      [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    fi
    ;;

  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;

  *)
    echo "用法: $0 {start|stop|status|restart}"
    exit 1
    ;;
esac
