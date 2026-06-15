# 🎯 Job Hunter — AI 求职助手

> 你负责投简历，AI 负责发现岗位、评估匹配度、生成投递方案。
> 基于 Loop Engineering，7×24 自动运转，不需要你盯。

> ⚠️ 说明：这是一个 Loop Engineering 学习参考项目，不是成熟 SaaS 产品。项目由 Hermes Agent 初步开发，后续由 Codex 做了迭代优化；欢迎基于实际使用继续 contribute。

## 它能做什么

```
每 4 小时自动搜索招聘平台新岗位（默认智联招聘，避免高频触发 Boss 直聘风控）
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
- 📊 **市场情报和周报**：沉淀岗位市场数据，生成趋势摘要
- 🎯 **面试准备和看板**：已投递岗位自动进入准备任务和进度看板
- 🔒 **合规安全**：只读搜索，绝不自动投递，投递由你手动完成

## 快速开始

```bash
# 1. Clone 到 Hermes 工作空间
git clone https://github.com/comeonzhj/job-hunter.git ~/.hermes/job-hunter

# 2. 告诉 Agent 完成配置
#    在 Hermes 中发送：
#    "阅读 $JOB_HOME/SETUP.md，按引导完成项目配置"
```

Agent 会自动检查依赖、引导你填写配置、询问是否提供简历作为筛选参考。
需要你配合的步骤（如 Boss 直聘扫码登录），Agent 会告诉你怎么做。

测评阶段不会自动创建定时任务；只有你明确说“启用长期任务”后再开启。

## 使用前必读

- **招聘平台风险**：`boss-agent-cli` 可能触发招聘平台风控，尤其是 BOSS 直聘。请低频、只读、谨慎使用；不要自动投递、自动打招呼或批量触达招聘者。
- **Agent 适配范围**：本项目只在 Hermes Agent 的任务触发、工作目录、Skill 加载和飞书链路下做过验证。其他 Agent 需要按自身机制适配触发方式、上下文注入、Skill 格式和定时任务。
- **项目性质**：本项目主要用于学习 Loop Engineering 的工程思路：外部触发器、任务队列、跨 session 记忆、文档反馈和审计链。代码仍有不少缺陷，欢迎提交 Issue / PR。
- **合规边界**：系统只做岗位发现、评估和投递建议；投递、沟通、联系方式交换等敏感动作必须由用户手动完成。

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

进阶脚本：
- `04-market-intel.sh`：生成岗位市场情报快照
- `05-weekly-report.sh`：生成求职周报草稿
- `06-interview-prep.sh`：对已投递岗位触发面试准备
- `09-kanban-sync.sh`：同步本地求职进度看板，可选同步飞书 Base

详细架构和进阶玩法见 [`scripts/advanced-features.md`](scripts/advanced-features.md)。

## 自定义路径

默认安装在 `~/.hermes/job-hunter/`。自定义：

```bash
export JOB_HOME=/your/custom/path
```

所有脚本都会优先读取 `JOB_HOME`，不会要求项目必须放在 `~/.hermes/job-hunter/`。

## 依赖

- [Hermes Agent](https://hermes-agent.nousresearch.com)
- [boss-agent-cli](https://github.com/can4hou6joeng4/boss-agent-cli)（默认使用 `--platform zhilian`）
- [lark-cli](https://github.com/nicepkg/lark-cli)（飞书集成）

## 已知限制

- `boss-agent-cli` 的不同版本参数可能变化，当前脚本按 `boss --platform <name> --json ...` 适配。
- 飞书文档、消息和事件监听依赖 `lark-cli` 授权与企业应用权限；权限不足时需要用户补授权。
- 事件监听和文档轮询是轻量实现，不包含生产级锁、并发控制和消息幂等保障。
- `queue.jsonl` / `seen.jsonl` 适合个人轻量使用；多人、多任务并发场景建议换成数据库。
- 文档 checkbox / 评论解析依赖飞书导出的 Markdown 结构，复杂文档格式可能需要额外适配。
- 周报、市场情报、看板目前是最小可用实现，统计维度和可视化仍比较粗糙。
- 其他 Agent 运行时可能不会自动读取 `workspace/AGENT.md` 或项目 Skills，需要自行改造初始化提示和触发脚本。
