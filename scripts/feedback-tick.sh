#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# feedback-tick.sh — 反馈检查脚本（Hermes cron script 模式）
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

TIMEOUT_HOURS=$(jq -r '.schedule.feedback_timeout_hours // 72' "$JOB_CONFIG")
REMINDER_HOURS=$(jq -r '.schedule.reminder_after_hours // 48' "$JOB_CONFIG")
NOW_EPOCH=$(date +%s)

log_event() {
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg type "$1" \
    --arg detail "$2" \
    '{timestamp: $ts, event: $type, detail: $detail}' >> "$JOB_AUDIT"
}

log_event "feedback_tick_start" "checking feedback and doc status"

OUTPUT_ITEMS=()

parse_epoch() {
  local value="$1"
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$value" +%s 2>/dev/null \
    || date -d "$value" +%s 2>/dev/null \
    || echo "0"
}

# ── 第 1 步: 检测文档交互 ──
DOC_FEEDBACK=$(bash "$JOB_SCRIPTS/03-check-feedback.sh" 2>/dev/null || echo '{"ok":false}')

if echo "$DOC_FEEDBACK" | jq -e '.ok == true and .event_count > 0' &>/dev/null; then
  EVENT_COUNT=$(echo "$DOC_FEEDBACK" | jq '.event_count')
  log_event "doc_activity_detected" "$EVENT_COUNT batches with activity"
  OUTPUT_ITEMS+=("📋 检测到 $EVENT_COUNT 个批次有用户文档活动")
  OUTPUT_ITEMS+=("$(echo "$DOC_FEEDBACK" | jq -c '.events')")
fi

# ── 第 1.5 步: 已投递岗位触发面试准备 ──
INTERVIEW_OUTPUT=$(bash "$JOB_SCRIPTS/06-interview-prep.sh" 2>/dev/null || true)
if [ -n "$INTERVIEW_OUTPUT" ]; then
  log_event "interview_prep_triggered" "interview prep script produced output"
  OUTPUT_ITEMS+=("$INTERVIEW_OUTPUT")
fi

# ── 第 2 步: 检查超时 ──
if [ -s "$JOB_QUEUE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    STATUS=$(echo "$line" | jq -r '.status')
    [ "$STATUS" != "waiting_feedback" ] && continue
    
    BATCH_ID=$(echo "$line" | jq -r '.batch_id')
    TIMESTAMP=$(echo "$line" | jq -r '.timestamp')
    BATCH_EPOCH=$(parse_epoch "$TIMESTAMP")
    HOURS_SINCE=$(( (NOW_EPOCH - BATCH_EPOCH) / 3600 ))
    
    if [ "$HOURS_SINCE" -ge "$TIMEOUT_HOURS" ]; then
      TMPFILE="$JOB_QUEUE.tmp"
      jq -c "if .batch_id == \"$BATCH_ID\" then .status = \"auto_archived\" else . end" \
        "$JOB_QUEUE" > "$TMPFILE" && mv "$TMPFILE" "$JOB_QUEUE"
      
      REPORT_PATH=$(echo "$line" | jq -r '.report_path // empty')
      if [ -n "$REPORT_PATH" ] && [ -f "$REPORT_PATH" ]; then
        mv "$REPORT_PATH" "$JOB_WORKSPACE/archives/" 2>/dev/null || true
      fi
      
      log_event "auto_archive" "batch=$BATCH_ID after ${HOURS_SINCE}h"
      OUTPUT_ITEMS+=("📦 批次 $BATCH_ID 已自动归档（${HOURS_SINCE}小时未处理）")
      
    elif [ "$HOURS_SINCE" -ge "$REMINDER_HOURS" ]; then
      JOB_COUNT=$(echo "$line" | jq '.job_count')
      REMAINING=$(( TIMEOUT_HOURS - HOURS_SINCE ))
      log_event "reminder" "batch=$BATCH_ID after ${HOURS_SINCE}h"
      OUTPUT_ITEMS+=("⏰ 批次 $BATCH_ID 已等待 ${HOURS_SINCE}h（${JOB_COUNT} 个岗位）。${REMAINING}h 后自动归档。")
    fi
  done < <(jq -c '.' "$JOB_QUEUE" 2>/dev/null || true)
fi

# ── 输出 ──
if [ ${#OUTPUT_ITEMS[@]} -eq 0 ]; then
  log_event "feedback_tick_end" "nothing to report"
  exit 0
fi

log_event "feedback_tick_end" "${#OUTPUT_ITEMS[@]} items"
printf '%s\n' "${OUTPUT_ITEMS[@]}"

# 更新本地求职看板，不因同步失败影响反馈循环。
bash "$JOB_SCRIPTS/09-kanban-sync.sh" >/dev/null 2>&1 || true
