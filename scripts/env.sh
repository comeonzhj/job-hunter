#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# env.sh — 全局环境变量（所有脚本 source 此文件）
#
# 用户自定义方式:
#   export JOB_HOME=/path/to/job-hunter   (在 .bashrc 或 .profile)
#   或修改下面的默认值
# ──────────────────────────────────────────────────────────────

# 项目根目录（用户可自定义）
export JOB_HOME="${JOB_HOME:-$HOME/.hermes/job-hunter}"

# 子目录
export JOB_SCRIPTS="$JOB_HOME/scripts"
export JOB_WORKSPACE="$JOB_HOME/workspace"
export JOB_CONFIG="$JOB_HOME/config.json"

# 工作空间文件
export JOB_QUEUE="$JOB_WORKSPACE/queue.jsonl"
export JOB_SEEN="$JOB_WORKSPACE/seen.jsonl"
export JOB_FEEDBACK="$JOB_WORKSPACE/feedback.jsonl"
export JOB_PREFERENCES="$JOB_WORKSPACE/preferences.json"
export JOB_AUDIT="$JOB_WORKSPACE/audit.jsonl"
export JOB_DOC_STATE="$JOB_WORKSPACE/.doc-state"

# 事件驱动相关
export JOB_EVENTS="$JOB_WORKSPACE/events"
export JOB_EVENTS_PROCESSED="$JOB_WORKSPACE/events/.processed"
export JOB_LISTENER_PID="$JOB_WORKSPACE/.listener.pid"
export JOB_LISTENER_LOG="$JOB_WORKSPACE/event-listener.log"

# Hermes scripts 目录（cron job 从这里加载）
export HERMES_SCRIPTS="${HERMES_SCRIPTS:-$HOME/.hermes/scripts}"

# 确保目录存在
mkdir -p "$JOB_WORKSPACE"/{reports,archives,.doc-state,events/.processed}
touch "$JOB_QUEUE" "$JOB_SEEN" "$JOB_AUDIT"
