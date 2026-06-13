# 🎯 Job Hunter — AI 求职助手

> 你负责投简历，AI 负责发现岗位、评估匹配度、生成投递方案。
> 基于 Loop Engineering，7×24 自动运转，不需要你盯。

## 它能做什么

```
每 4 小时自动搜索 Boss 直聘新岗位
    ↓
6 维度智能评分（技能/薪资/地域/公司/福利/发展）
    ↓
生成可交互的飞书投递报告（打勾 = 感兴趣）
    ↓
你标记感兴趣 → AI 生成定制投递方案
你没反馈     → 48h 提醒 → 72h 归档（不卡等你）
```

**核心特性**：
- 📡 **事件驱动**：飞书消息秒级触发，不需要你主动通知
- 📄 **文档即界面**：在飞书文档里打勾就是反馈，零操作成本
- 🧠 **越用越懂你**：从你的每次反馈（包括沉默）中学习偏好
- 🔒 **合规安全**：只读搜索，绝不自动投递，投递由你手动完成

## 快速开始

```bash
# 1. Clone 到 Hermes 工作空间
git clone https://github.com/comeonzhj/job-hunter.git ~/.hermes/job-hunter

# 2. 告诉 Agent 完成配置
#    在 Hermes 中发送：
#    "阅读 ~/.hermes/job-hunter/SETUP.md，按引导完成项目配置"
```

Agent 会自动检查依赖、引导你填写配置、启动事件监听、创建定时任务。
需要你配合的步骤（如 Boss 直聘扫码登录），Agent 会告诉你怎么做。

## 架构（给技术人看的）

```
事件驱动层（实时）          定时轮询层（兜底）
飞书 WebSocket → 事件队列    cron 4h → 搜索 → diff
     ↓                            ↓
     └────────── 合并 ─────────────┘
                    ↓
            Agent（被动响应式）
            加载 Skills → 执行 SOP → 交付文档
                    ↓
            用户反馈（checkbox/消息）
                    ↓
            偏好模型更新 → 下轮更精准
```

三层组件：
- **循环控制器**：event-listener + event-dispatcher + cron scripts
- **Skills**：job-hunter-sop / delivery / feedback（标准 Hermes Skill 格式）
- **工作空间**：队列、偏好模型、事件日志、审计追踪

详细架构和进阶玩法见 [`scripts/advanced-features.md`](scripts/advanced-features.md)。

## 自定义路径

默认安装在 `~/.hermes/job-hunter/`。自定义：

```bash
export JOB_HOME=/your/custom/path
```

## 依赖

- [Hermes Agent](https://hermes-agent.nousresearch.com)
- [boss-agent-cli](https://github.com/can4hou6joeng4/boss-agent-cli)
- [lark-cli](https://github.com/nicepkg/lark-cli)（飞书集成）
