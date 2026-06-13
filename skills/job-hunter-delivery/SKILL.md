---
name: job-hunter-delivery
description: "Use when delivering job application reports to Feishu. Provides interactive document templates with checkbox feedback, message notification formats, and degradation strategies."
version: 2.0.0
author: Job Hunter System
license: MIT
metadata:
  hermes:
    tags: [feishu, delivery, interactive-docs, feedback-ui]
    related_skills: [job-hunter-sop, job-hunter-feedback]
---

# Job Hunter Delivery — 飞书交付规范

## Overview

投递报告的飞书交付不是"写一个文档发个链接"，而是**构建一个交互界面**。用户在文档中打勾、评论就是反馈信号，系统通过轮询文档检测用户行为。

核心理念：**文档即界面，反馈即信号。**

## When to Use

- 需要创建投递报告飞书文档
- 需要发送报告通知消息
- 需要设计可交互的反馈机制

## 文档结构模板

### XML 格式（推荐）

```xml
<title>📋 岗位投递报告 — {date}</title>

<callout emoji="📊" background-color="light-blue">
<p><b>批次</b>: {batch_id} | <b>新增</b>: {total} 个 | <b>搜索时间</b>: {timestamp}</p>
<p>⭐ 强烈推荐: {high} 个 | 📌 建议投递: {mid} 个 | 📎 可考虑: {low} 个</p>
</callout>

<callout emoji="🎯" background-color="light-green">
<p><b>操作指南</b>: 勾选你感兴趣的岗位，我将生成投递方案。</p>
<p>• 勾选 = 感兴趣 → 生成投递方案 | • 不勾选 = 跳过 | • 底部评论 = 补充说明</p>
</callout>

<h2>⭐ 强烈推荐投递</h2>
{for each high_score_job}
<callout emoji="🏢" background-color="light-gray">
<p><b>{序号}. {title}</b> @ <b>{company}</b></p>
<p>💰 {salary} | 📍 {city} | 🎯 匹配度: <b>{score}/10</b></p>
<p><b>推荐理由:</b> {reason}</p>
<p><b>简历优化:</b> {resume_tips}</p>
<p><b>投递话术:</b> {greeting_draft}</p>
</callout>
{end for}

<h2>📌 建议投递</h2>
{for each mid_score_job}
<p><b>{序号}. {title}</b> @ {company} | {salary} | 匹配度: {score}/10</p>
<p>　　{brief_reason}</p>
{end for}

<h2>✅ 标记你的意向</h2>
<callout emoji="👇" background-color="light-yellow">
<p>勾选你感兴趣的岗位（打勾 = 感兴趣）:</p>
</callout>
{for each all_jobs}
<checkbox>{序号}. {title} @ {company} | {salary}</checkbox>
{end for}

<h2>💬 补充反馈</h2>
<callout emoji="💬" background-color="light-purple">
<p>在文档任意位置添加评论。例如: "薪资太低" / "已投过了" / "帮我重点看第 3 个"</p>
</callout>
```

### Markdown 降级

当 XML 不可用时：

```markdown
# 📋 岗位投递报告 — {date}

> 批次: {batch_id} | 新增: {total} 个

## ✅ 标记你的意向
- [ ] 1. {title} @ {company} | {salary} | ⭐{score}
- [ ] 2. {title} @ {company} | {salary} | 📌{score}

**编辑此文件打勾后保存即可。**

## ⭐ 强烈推荐
### 1. {title} @ {company}
- 💰 {salary} | 📍 {city} | 🎯 {score}/10
- **推荐理由**: {reason}
- **简历优化**: {resume_tips}
```

## 消息通知模板

### 报告通知
```
📋 新的投递报告已生成！
📊 本轮: {count} 个新岗位 | ⭐ 强烈推荐: {high} 个
👉 查看报告: {doc_url}
在文档中勾选你感兴趣的岗位，我来生成投递方案。
```

### 48h 提醒
```
⏰ 你有 {count} 个岗位等待决策
Top 3: {list}
👉 {doc_url}
不做任何操作将在 {remaining}h 后自动归档。
```

## 降级策略

| 场景 | 方案 |
|------|------|
| XML 文档创建失败 | 降级 Markdown 模板 |
| 文档创建完全失败 | 纯消息发送摘要 |
| 消息发送失败 | 本地保存，下次 tick 重试 |
| lark-cli 不可用 | 本地 .md 文件 |

## Common Pitfalls

1. **checkbox 格式不对**：必须用 `- [ ]` 前缀，否则 03-check-feedback.sh 的 grep 匹配不到
2. **doc_token 未回写队列**：创建文档后必须把 doc_token 写回 queue.jsonl，否则反馈检测找不到文档
3. **文档内容太长**：单文档建议不超过 15 个岗位，否则用户阅读成本过高

## Verification Checklist

- [ ] 文档包含 checkbox 反馈区
- [ ] checkbox 格式为 `- [ ]`
- [ ] doc_token 已回写到 queue.jsonl
- [ ] 消息通知已发送
- [ ] 文档链接可访问
