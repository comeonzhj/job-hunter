#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 03-check-feedback.sh — 文档交互状态检测
#
# 检测维度:
#   1. checkbox 状态变化
#   2. 文档评论
#   3. 与上次快照对比
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

log_event() {
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg type "$1" \
    --arg detail "$2" \
    '{timestamp: $ts, event: $type, detail: $detail}' >> "$JOB_AUDIT"
}

if [ ! -s "$JOB_QUEUE" ]; then
  echo '{"ok":true,"events":[],"message":"no pending batches"}'
  exit 0
fi

WAITING_BATCHES=$(jq -c 'select(.status == "waiting_feedback")' "$JOB_QUEUE" 2>/dev/null || true)
if [ -z "$WAITING_BATCHES" ]; then
  echo '{"ok":true,"events":[],"message":"no batches waiting for feedback"}'
  exit 0
fi

ALL_EVENTS="[]"

while IFS= read -r batch; do
  [ -z "$batch" ] && continue
  
  BATCH_ID=$(echo "$batch" | jq -r '.batch_id')
  DOC_TOKEN=$(echo "$batch" | jq -r '.doc_token // empty')
  
  if [ -z "$DOC_TOKEN" ]; then
    continue
  fi
  
  STATE_FILE="$JOB_DOC_STATE/$BATCH_ID.json"
  
  # 获取文档内容
  DOC_CONTENT=$(lark-cli docs +fetch \
    --doc "$DOC_TOKEN" \
    --format json 2>/dev/null || echo '{"ok":false}')
  
  if echo "$DOC_CONTENT" | jq -e '.ok != true' &>/dev/null; then
    log_event "doc_fetch_failed" "batch=$BATCH_ID token=$DOC_TOKEN"
    continue
  fi
  
  MARKDOWN=$(echo "$DOC_CONTENT" | jq -r '.data.markdown // .data.document.markdown // ""')
  
  # 提取 checkbox 状态
  CURRENT_CHECKBOXES=$(echo "$MARKDOWN" | grep -oE '^\s*-\s*\[([ xX])\].*$' | \
    sed 's/^\s*-\s*\[/[/' | \
    jq -R -s 'split("\n") | map(select(length > 0)) | to_entries | map({
      index: .key,
      checked: (test("\\[[xX]\\]")),
      text: .value
    })' 2>/dev/null || echo "[]")
  
  # 提取评论
  COMMENTS=$(lark-cli drive list-comments \
    --file-token "$DOC_TOKEN" \
    --format json 2>/dev/null || echo '{"ok":false}')
  
  CURRENT_COMMENTS="[]"
  if echo "$COMMENTS" | jq -e '.ok == true' &>/dev/null; then
    CURRENT_COMMENTS=$(echo "$COMMENTS" | jq '[.data.items[]? | {
      id: .comment_id,
      text: (.reply_list.replies[0].content.elements[0].text_run.content // ""),
      user: (.reply_list.replies[0].user_id // "unknown"),
      timestamp: (.reply_list.replies[0].create_time // "0")
    }]')
  fi
  
  # 与上次状态对比
  if [ -f "$STATE_FILE" ]; then
    PREV_CHECKBOXES=$(jq -c '.checkboxes // []' "$STATE_FILE")
    PREV_COMMENTS=$(jq -c '.comments // []' "$STATE_FILE")
  else
    PREV_CHECKBOXES="[]"
    PREV_COMMENTS="[]"
  fi
  
  # 检测变化
  NEWLY_CHECKED=$(jq -n --argjson curr "$CURRENT_CHECKBOXES" --argjson prev "$PREV_CHECKBOXES" '
    [$curr[] | select(.checked == true) | .index] as $c |
    [$prev[] | select(.checked == true) | .index] as $p |
    [$c[] | select(. as $i | $p | index($i) | not)]
  ')
  
  PREV_COMMENT_IDS=$(echo "$PREV_COMMENTS" | jq '[.[].id]')
  NEW_COMMENTS=$(jq -n --argjson curr "$CURRENT_COMMENTS" --argjson prev_ids "$PREV_COMMENT_IDS" '
    [$curr[] | select(.id as $id | $prev_ids | index($id) | not)]
  ')
  
  CHECKED_COUNT=$(echo "$NEWLY_CHECKED" | jq 'length')
  COMMENT_COUNT=$(echo "$NEW_COMMENTS" | jq 'length')
  
  if [ "$CHECKED_COUNT" -gt 0 ] || [ "$COMMENT_COUNT" -gt 0 ]; then
    EVENT=$(jq -n \
      --arg batch_id "$BATCH_ID" \
      --arg doc_token "$DOC_TOKEN" \
      --argjson newly_checked "$NEWLY_CHECKED" \
      --argjson new_comments "$NEW_COMMENTS" \
      --argjson checkbox_snapshot "$CURRENT_CHECKBOXES" \
      '{
        batch_id: $batch_id,
        doc_token: $doc_token,
        newly_checked_indices: $newly_checked,
        new_comments: $new_comments,
        checkbox_snapshot: $checkbox_snapshot,
        has_activity: true
      }')
    
    ALL_EVENTS=$(jq -n --argjson events "$ALL_EVENTS" --argjson event "$EVENT" '$events + [$event]')
    log_event "doc_activity" "batch=$BATCH_ID checked=$CHECKED_COUNT comments=$COMMENT_COUNT"
  fi
  
  # 保存当前状态
  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson checkboxes "$CURRENT_CHECKBOXES" \
    --argjson comments "$CURRENT_COMMENTS" \
    '{last_checked: $ts, checkboxes: $checkboxes, comments: $comments}' > "$STATE_FILE"

done <<< "$WAITING_BATCHES"

EVENT_COUNT=$(echo "$ALL_EVENTS" | jq 'length')

if [ "$EVENT_COUNT" -eq 0 ]; then
  echo '{"ok":true,"events":[],"message":"no user activity detected"}'
  exit 0
fi

echo "$ALL_EVENTS" | jq '{
  ok: true,
  event_count: length,
  events: .,
  message: ("检测到 " + (length | tostring) + " 个批次有用户活动")
}'
