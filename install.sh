#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# install.sh — 轻量安装脚本（命令行用户备选）
#
# 推荐方式：让 Agent 阅读 SETUP.md 自动完成配置。
# 本脚本仅用于偏好命令行的用户。
# ──────────────────────────────────────────────────────────────
set -euo pipefail

INSTALL_DIR="${JOB_HOME:-$HOME/.hermes/job-hunter}"
HERMES_SCRIPTS="${HERMES_SCRIPTS:-$HOME/.hermes/scripts}"

echo "🎯 Job Hunter 安装（命令行模式）"
echo "推荐方式: 让 Agent 阅读 SETUP.md 自动配置"
echo "=================================="

# 检查依赖
MISSING=0
for cmd in python3 jq boss lark-cli; do
  command -v "$cmd" &>/dev/null && echo "  ✅ $cmd" || { echo "  ❌ $cmd"; MISSING=1; }
done
[ $MISSING -eq 1 ] && { echo "⚠️ 有依赖缺失"; exit 1; }

# 创建目录
mkdir -p "$INSTALL_DIR"/{workspace/{reports,archives,.doc-state,events/.processed},scripts}

# 同步脚本
cp "$INSTALL_DIR"/scripts/loop-tick.sh "$HERMES_SCRIPTS/job-hunter-tick.sh" 2>/dev/null || true
cp "$INSTALL_DIR"/scripts/feedback-tick.sh "$HERMES_SCRIPTS/job-hunter-feedback.sh" 2>/dev/null || true
cp "$INSTALL_DIR"/scripts/event-dispatcher.sh "$HERMES_SCRIPTS/job-hunter-event-dispatcher.sh" 2>/dev/null || true
chmod +x "$HERMES_SCRIPTS"/job-hunter-*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/scripts/*.sh

# Skills 符号链接
for skill in job-hunter-sop job-hunter-delivery job-hunter-feedback; do
  ln -sf "$INSTALL_DIR/skills/$skill" "$HOME/.hermes/skills/content/$skill" 2>/dev/null || true
done

# 初始化数据
touch "$INSTALL_DIR/workspace"/{queue.jsonl,seen.jsonl,feedback.jsonl,audit.jsonl}

echo ""
echo "✅ 文件就绪。还需手动完成:"
echo "  1. vim $INSTALL_DIR/config.json"
echo "  2. boss login"
echo "  3. bash $INSTALL_DIR/scripts/event-listener.sh start"
echo "  4. 创建 cron jobs（见 README.md）"
