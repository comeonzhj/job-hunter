---
name: job-hunter-feedback
description: "Use when user provides feedback on job application reports (checkbox, comments) or when feedback signals need to be processed. Analyzes feedback, updates preference model, and iterates filtering rules."
version: 1.0.0
author: Job Hunter System
license: MIT
metadata:
  hermes:
    tags: [feedback, learning, preference-model, loop-engineering]
    related_skills: [job-hunter-sop, job-hunter-delivery]
---

# Job Hunter Feedback — 反馈驱动的遴选迭代

## Overview

用户的每次反馈（包括沉默）都是信号。本 Skill 定义如何解析反馈信号、更新偏好模型、调整后续搜索和评分策略。

核心理念：**反馈不是终点，是下一轮循环的起点。**

## When to Use

- 03-check-feedback.sh 检测到用户勾选了文档中的 checkbox
- 03-check-feedback.sh 检测到文档新增评论
- feedback-tick.sh 输出超时提醒或归档通知
- 需要根据累积反馈调整搜索和评分策略

## 反馈信号分类

| 信号 | 含义 | 强度 | 系统动作 |
|------|------|------|---------|
| ✅ 勾选 checkbox | 感兴趣 | +3 | 提取特征 → 强化相似岗位 |
| ❌ 取消勾选 | 改变主意 | -2 | 记录 → 降低相似权重 |
| 💬 "薪资低" | 明确拒绝 | -3 | 更新薪资下限 |
| 💬 "技术不匹配" | 技能不匹配 | -2 | 更新技能权重 |
| 💬 "已投"/"已面" | 已消费 | 0 | 设置 `pipeline_status=applied` → 运行 `06-interview-prep.sh` |
| 💬 正向评论 | 补充偏好 | +2 | 加入正向特征 |
| ⏰ 48h 无操作 | 弱负 | -0.5 | 微调阈值 |
| 📦 72h 归档 | 沉默信号 | -1 | 强化排除特征 |

## Step 1: 解析反馈事件

```bash
# 读取反馈事件（来自 03-check-feedback.sh 输出）
# events[].newly_checked_indices → 哪些 checkbox 被勾选
# events[].new_comments → 新增评论内容
# events[].checkbox_snapshot → 当前完整状态
```

## Step 2: 岗位特征提取

对用户标记 ✅ 的岗位，提取共同特征：

| 维度 | 来源 | 存储字段 |
|------|------|---------|
| 技术栈 | JD 关键词 | `preferred_skills` |
| 公司阶段 | 融资/规模 | `preferred_company_stage` |
| 薪资区间 | 岗位薪资 | `salary_range_update` |
| 行业 | 公司行业 | `preferred_industry` |

对拒绝的岗位，提取排斥特征：`excluded_keywords`、`excluded_jd_patterns`

## Step 3: 更新偏好模型

```bash
PREF_FILE=$JOB_PREFERENCES

# 读取当前偏好
CURRENT=$(cat "$PREF_FILE" 2>/dev/null || echo '{}')

# 合并新信号（由 Agent 执行 jq/python 更新）
# 更新 preferred_skills 权重
# 更新 excluded_keywords
# 更新 salary_preference
# 递增 signals_received 计数器
```

偏好模型结构见 `$JOB_WORKSPACE/preferences.json`。

## Step 4: 搜索策略调整

| 偏好变化 | 搜索调整 |
|---------|---------|
| `preferred_skills` 权重 > 0.7 | 加入搜索关键词 |
| `excluded_keywords` 新增 | 加入排除过滤 |
| `salary_preference.min` 更新 | 调整薪资参数 |
| 连续 3 批无高分岗位 | 降低阈值 / 扩大范围 |

岗位状态发生变化后，必须运行：

```bash
bash $JOB_SCRIPTS/09-kanban-sync.sh
```

如果出现 `pipeline_status=applied` 的岗位，必须运行：

```bash
bash $JOB_SCRIPTS/06-interview-prep.sh
```

## Step 5: 生成迭代报告

```markdown
# 🔄 遴选规则迭代报告
## 本轮反馈
- ✅ 感兴趣: {n} 个 | ❌ 不感兴趣: {n} 个 | 💬 评论: {n} 条
## 学到的偏好
- 新增正向: {features}
- 新增排斥: {features}
## 下轮调整
- 搜索关键词: {changes}
- 评分权重: {changes}
## 偏好模型成熟度: {bar} {percent}%
```

## 沉默信号处理

| 无反馈时长 | 解读 | 动作 |
|-----------|------|------|
| 0-24h | 正常 | 蛰伏 |
| 48h | 不够吸引 | 发精简提醒（top 3） |
| 72h | 不感兴趣 | 归档，记录弱负信号 |
| 连续 3 批 | 系统问题 | 检查策略，发诊断 |

**关键**：沉默信号强度**不应等于明确拒绝**。它是弱信号，连续累积才会产生显著影响。

## 偏好模型生命周期

```
冷启动 (0-10 信号) → 基于 config.json，高探索性
学习期 (10-50) → 偏好开始显现，排除列表稳定
稳定期 (50-100) → 推荐精准度显著提升
自适应期 (100+) → 检测偏好漂移，主动询问是否调整方向
```

## Common Pitfalls

1. **过度推断沉默信号**：一次无反馈不代表不感兴趣，不应仅凭沉默就排除
2. **偏好更新无归一化**：权重调整后必须归一化，否则评分体系会失衡
3. **未记录迭代历史**：每次偏好变更都要有审计日志，否则无法追溯
4. **忽略偏好漂移**：长期运行后用户方向可能变化，应主动检测

## Verification Checklist

- [ ] 反馈事件已解析并分类
- [ ] 偏好模型已更新（`preferences.json`）
- [ ] 权重已归一化
- [ ] 审计日志已写入
- [ ] 迭代报告已生成（可选）
