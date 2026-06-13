---
name: job-hunter-sop
description: "Use when Agent is triggered by job-hunter cron with new job listings. Evaluates job matches using 6-dimension scoring, generates application reports, and delivers via Feishu documents."
version: 1.0.0
author: Job Hunter System
license: MIT
metadata:
  hermes:
    tags: [job-search, evaluation, feishu, loop-engineering]
    related_skills: [job-hunter-delivery, job-hunter-feedback]
---

# Job Hunter SOP — 岗位评估标准作业流程

## Overview

当 Agent 被 `loop-tick.sh` 唤醒并收到新岗位通知时，按本 Skill 执行完整评估流程：获取详情 → 6 维度评分 → 生成投递报告 → 交付飞书文档 → 等待用户反馈。

本 Skill 是 Loop Engineering 中"Executor"角色的规范化表达。

## When to Use

- 收到 cron 输出中包含"发现 X 个新岗位"
- 消息引用了 `$JOB_HOME/workspace/queue.jsonl`
- 需要评估岗位匹配度并生成投递报告

## 前置检查

```bash
# 1. 读取环境配置
source $JOB_HOME/scripts/env.sh

# 2. 读取用户配置
cat $JOB_CONFIG

# 3. 读取偏好模型（如有）
cat $JOB_PREFERENCES 2>/dev/null || echo "无偏好模型，使用初始配置"

# 4. 读取待处理队列
jq -c 'select(.status == "pending")' $JOB_QUEUE
```

## Step 1: 获取岗位详情

对队列中每个岗位调用 `boss detail`：

```bash
boss detail <security_id> --format json
```

**关键字段**：职位名称、薪资、地点、公司名称/规模/融资阶段、JD 全文、福利列表、招聘者信息。

**批量限制**：每批最多 5 个，请求间隔 2 秒。

## Step 2: 6 维度匹配度评分

| 维度 | 权重 | 评分要点 |
|------|------|---------|
| 技能匹配 | 30% | JD 技术栈与求职者技能的重合度。读取 `preferences.json` 中的 `preferred_skills` 加权 |
| 薪资匹配 | 20% | 是否在期望范围。参考 `preferences.json` 中的 `salary_preference` |
| 地域匹配 | 15% | 是否在目标城市或可接受远程 |
| 公司质量 | 15% | 融资阶段、规模、行业口碑 |
| 福利匹配 | 10% | 双休、五险一金等核心福利 |
| 发展空间 | 10% | JD 中的成长性信号（新业务、核心技术、团队规模） |

**评分等级**：
- ≥ 8 分：⭐⭐⭐ 强烈推荐
- 6-7.9 分：⭐⭐ 建议投递
- 4-5.9 分：⭐ 可考虑
- < 4 分：不推荐

## Step 3: 生成投递报告

按 `$JOB_SCRIPTS/feishu-delivery.md` 中的文档模板生成报告。

报告必须包含：
1. 概览区（callout 高亮关键数字）
2. 分级展示（强烈推荐 → 建议 → 可考虑 → 不推荐）
3. 每个推荐岗位的理由、简历优化点、投递话术
4. **可交互反馈区**（checkbox + 评论引导）

## Step 4: 交付飞书文档

```bash
# 创建文档
lark-cli docs +create --content '...' --format json

# 记录 doc_token 到队列
jq -c "select(.batch_id == \"$BATCH_ID\") |= . + {doc_token: \"$DOC_TOKEN\", doc_url: \"$DOC_URL\", status: \"waiting_feedback\", report_path: \"$REPORT_PATH\"}" $JOB_QUEUE > $JOB_QUEUE.tmp && mv $JOB_QUEUE.tmp $JOB_QUEUE
```

## Step 5: 发送通知

通过飞书消息通知用户报告已生成，包含文档链接。

## Step 6: 审计日志

```bash
# 写入审计
jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg type "report_generated" --arg detail "batch=$BATCH_ID jobs=$COUNT" '{timestamp: $ts, event: $type, detail: $detail}' >> $JOB_AUDIT
```

## 合规红线

- **绝不自动投递**
- **绝不自动打招呼**
- **绝不代替用户操作 Boss 直聘**
- 所有敏感操作必须由用户在平台手动完成

## Common Pitfalls

1. **未读取 preferences.json 就评分**：偏好模型会显著影响评分结果，必须每次都读取
2. **checkbox 格式错误**：飞书文档的 checkbox 必须用 `- [ ]` 格式，否则 03-check-feedback.sh 无法检测
3. **队列状态未更新**：报告交付后必须更新 status 为 waiting_feedback，否则 feedback-tick 会重复处理
4. **boss detail 超时**：单次请求可能超时，应有重试逻辑（最多 3 次）

## Verification Checklist

- [ ] 已读取 `preferences.json` 并应用到评分
- [ ] 报告包含可交互 checkbox 反馈区
- [ ] 文档已创建且 doc_token 已记录到队列
- [ ] 飞书消息通知已发送
- [ ] 审计日志已写入
- [ ] 队列状态已更新为 waiting_feedback
