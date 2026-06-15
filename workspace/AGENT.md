# Job Hunter — 求职岗位自动发现系统

> 本文档由 Hermes 自动注入到每个 session 的 system prompt。
> 它是跨 session 的"共享记忆"，确保每次 Agent 被唤醒时都了解整体状态。

## 系统概述

基于 Loop Engineering 的长期求职辅助系统。三层架构：
- **循环控制器**: 事件驱动（飞书 WebSocket）+ 定时轮询（cron）双通道
- **Skills**: job-hunter-sop / job-hunter-delivery / job-hunter-feedback
- **工作空间**: `$JOB_HOME/workspace/` 下的队列、偏好、事件、审计

## 触发通道

### 通道 1: 事件驱动（实时）
- 飞书消息事件 → event-listener.sh → events/ 目录 → event-dispatcher.sh → Agent
- 用户在飞书聊天中发送反馈（Y/N/A）→ 即时触发
- reaction 事件（👍/👎）→ 补充信号

### 通道 2: 定时轮询（兜底）
- loop-tick.sh（每 4h）→ 搜索 + 文档状态检测
- feedback-tick.sh（每 12h）→ 超时检查 + 文档轮询兜底

### 通道 3: 文档反馈（准实时）
- 03-check-feedback.sh 轮询飞书文档 → 检测 checkbox / 评论变化
- 作为事件驱动的补充（文档编辑事件可能不可用时的降级方案）

## 关键路径

| 资源 | 路径 |
|------|------|
| 配置文件 | `$JOB_CONFIG` |
| 任务队列 | `$JOB_QUEUE` |
| 用户偏好模型 | `$JOB_PREFERENCES` |
| 事件队列 | `$JOB_EVENTS/` |
| 审计日志 | `$JOB_AUDIT` |
| 市场情报 | `$JOB_WORKSPACE/market-intel.json` |
| 求职看板 | `$JOB_WORKSPACE/kanban.csv` |
| 面试准备任务 | `$JOB_WORKSPACE/interview-prep-tasks.jsonl` |

## Agent 行为准则

1. **不卡等用户**: 交付报告后立即转 waiting_feedback
2. **合规红线**: 绝不自动投递、不自动打招呼
3. **读取偏好**: 每次评估前读取 preferences.json
4. **审计追踪**: 关键动作写入 audit.jsonl
5. **沉默保护**: 72h 无反馈 → 自动归档
6. **简历优先**: 如果 `config.json` 中配置了简历路径或摘要，评估和面试准备必须读取
7. **看板同步**: 每次岗位状态变化后运行 `09-kanban-sync.sh`

## 长期记忆分层

- `AGENT.md`：每个 session 都应先读的系统同频信息
- `config.json`：用户明确给出的稳定偏好、简历入口、交付渠道
- `preferences.json`：从反馈中学习出的动态偏好，只能基于信号渐进更新
- `queue.jsonl`：岗位批次、报告链接、pipeline 状态
- `audit.jsonl`：所有关键动作的可追溯日志
- `market-intel.json`：岗位市场快照，供周报和策略调整使用
- `kanban.csv`：面向用户的进度视图

## 事件路由规则

收到用户消息时，按以下规则路由：
- `Y 1,3` / `ALL Y` → 感兴趣，生成投递方案
- `N 2,4` → 不感兴趣，记录原因
- `A 5` → 已投递，加入跟踪
- 包含"已投"/"已面" → 触发面试准备任务
- 包含"报告"/"岗位" → 查询最新报告状态
- 其他消息 → 忽略（不属于本系统职责）
