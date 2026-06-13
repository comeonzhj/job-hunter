# SETUP.md — Agent 初始化指南

> **本文档面向 Agent（Hermes）。**
> 请严格按步骤执行，需要用户配合的步骤明确告知用户。

## 项目概述

Job Hunter 是一个基于 Loop Engineering 的长期求职辅助系统。
它通过飞书事件驱动 + 定时轮询，自动搜索 Boss 直聘岗位、评估匹配度、生成可交互的飞书投递报告。

**你的角色**：被动响应式 Agent。只有在收到触发事件后才工作。
**系统角色**：循环控制器（脚本）负责感知和调度，你负责推理和执行。

## 初始化步骤

按顺序执行以下步骤。每步完成后验证通过再进入下一步。

---

### Step 0: 环境变量

```bash
# 设置项目根目录（如果不在默认位置，修改这里）
export JOB_HOME="$HOME/.hermes/job-hunter"
```

后续所有步骤中 `$JOB_HOME` 代表项目根目录。

---

### Step 1: 检查依赖

逐个检查以下工具是否已安装：

```bash
command -v python3   # Python >= 3.10
command -v jq        # JSON 处理
command -v boss      # boss-agent-cli
command -v lark-cli  # 飞书 CLI
```

**如有缺失**，告知用户安装方式：
- `boss`：`uv tool install boss-agent-cli && patchright install chromium`
- `lark-cli`：`npm install -g lark-cli`
- `jq`：`apt install jq` 或 `brew install jq`

**全部通过后**进入下一步。

---

### Step 2: 引导用户填写配置

读取当前配置：

```bash
cat $JOB_HOME/config.json
```

向用户确认以下信息（用 clarify 工具）：

1. **目标城市**：你希望在哪个城市找工作？
2. **岗位关键词**：搜索哪些岗位？（如 "AI Agent", "大模型应用"）
3. **期望薪资范围**：最低和最高（单位 K）
4. **核心福利要求**：如 "双休", "五险一金"
5. **排除关键词**：不想看到的岗位特征（如 "外包", "驻场"）

用户回复后，更新配置文件：

```bash
# 用 write_file 或 patch 更新 $JOB_HOME/config.json
# 确保 JSON 格式正确
```

---

### Step 3: Boss 直聘登录

检查登录状态：

```bash
boss status --format json
```

如果 `ok == false`，告知用户：

> 请在终端运行 `boss login`，按提示扫码登录 Boss 直聘。
> 登录成功后告诉我。

用户确认后验证：

```bash
boss status --format json  # 确认 ok == true
```

---

### Step 4: 初始化工作空间

确保所有目录和文件存在：

```bash
mkdir -p $JOB_HOME/workspace/{reports,archives,.doc-state,events/.processed}
touch $JOB_HOME/workspace/{queue.jsonl,seen.jsonl,feedback.jsonl,audit.jsonl}
```

创建偏好模型初始文件（如不存在）：

```bash
cat > $JOB_HOME/workspace/preferences.json << 'EOF'
{
  "version": 1,
  "last_updated": "",
  "signals_received": 0,
  "learned_preferences": {},
  "learned_exclusions": {},
  "scoring_adjustments": {
    "skill_weight": 0.30,
    "salary_weight": 0.20,
    "location_weight": 0.15,
    "company_weight": 0.15,
    "welfare_weight": 0.10,
    "growth_weight": 0.10
  }
}
EOF
```

---

### Step 5: 注册 Skills

确认 Skills 目录存在：

```bash
ls $JOB_HOME/skills/job-hunter-*/SKILL.md
```

应该看到 3 个 Skill：
- `job-hunter-sop`
- `job-hunter-delivery`
- `job-hunter-feedback`

如果 Skills 不在 `~/.hermes/skills/` 中（Hermes 的默认加载路径），创建符号链接：

```bash
ln -sf $JOB_HOME/skills/job-hunter-sop ~/.hermes/skills/content/job-hunter-sop
ln -sf $JOB_HOME/skills/job-hunter-delivery ~/.hermes/skills/content/job-hunter-delivery
ln -sf $JOB_HOME/skills/job-hunter-feedback ~/.hermes/skills/content/job-hunter-feedback
```

---

### Step 6: 启动事件监听器

```bash
bash $JOB_HOME/scripts/event-listener.sh start
```

验证：

```bash
bash $JOB_HOME/scripts/event-listener.sh status
# 应该显示 "Listener 运行中"
```

如果启动失败（如 lark-cli 权限问题），告知用户检查飞书应用配置。

---

### Step 7: 同步脚本到 Hermes 目录

将 cron 需要的脚本复制到 `~/.hermes/scripts/`：

```bash
cp $JOB_HOME/scripts/loop-tick.sh ~/.hermes/scripts/job-hunter-tick.sh
cp $JOB_HOME/scripts/feedback-tick.sh ~/.hermes/scripts/job-hunter-feedback.sh
cp $JOB_HOME/scripts/event-dispatcher.sh ~/.hermes/scripts/job-hunter-event-dispatcher.sh
chmod +x ~/.hermes/scripts/job-hunter-*.sh
```

---

### Step 8: 创建定时任务

创建两个 cron job：

**主循环（每 4 小时）— 搜索 + 事件检测 + 文档轮询**：

```
cronjob(action='create',
  name='job-hunter-main',
  schedule='0 */4 * * *',
  script='job-hunter-tick.sh',
  no_agent=False,
  workdir='$JOB_HOME/workspace',
  prompt='你是求职助手。根据 cron 输出执行标准作业流程。如有新岗位，加载 job-hunter-sop skill 评估并交付报告。如有用户反馈，加载 job-hunter-feedback skill 处理。')
```

**反馈检查（每 12 小时）— 超时 + 归档**：

```
cronjob(action='create',
  name='job-hunter-feedback',
  schedule='0 */12 * * *',
  script='job-hunter-feedback.sh',
  no_agent=False,
  workdir='$JOB_HOME/workspace',
  prompt='你是求职助手。根据 cron 输出处理超时提醒和归档。如有待处理反馈，加载 job-hunter-feedback skill。')
```

记录返回的 job_id。

---

### Step 9: 验证全流程

运行一次手动测试：

```bash
bash $JOB_HOME/scripts/loop-tick.sh
```

检查审计日志：

```bash
cat $JOB_HOME/workspace/audit.jsonl | jq .
```

确认 cron jobs 已注册：

```
cronjob(action='list')
```

---

### Step 10: 汇报完成

向用户报告初始化结果：

```
✅ Job Hunter 初始化完成！

已配置:
  • 城市: {city}
  • 岗位: {keywords}
  • 薪资: {min}K - {max}K
  • 事件监听器: 运行中
  • 定时搜索: 每 4 小时 (job_id: xxx)
  • 反馈检查: 每 12 小时 (job_id: xxx)

工作方式:
  • 发现新岗位 → 自动生成飞书投递报告
  • 你在文档中打勾 = 感兴趣 → 我生成投递方案
  • 你在飞书聊天发 "Y 1,3" → 秒级响应
  • 72 小时无反馈 → 自动归档

需要你做的事:
  • 保持 boss login 登录态（过期需重新扫码）
  • 查看投递报告并标记意向
  • 其他事情交给我
```

---

## 异常处理

| 步骤 | 可能失败 | 处理方式 |
|------|---------|---------|
| Step 1 | 依赖缺失 | 列出缺失项和安装命令 |
| Step 3 | boss 登录失败 | 引导用户重新 login |
| Step 5 | Skills 链接失败 | 手动复制 SKILL.md |
| Step 6 | 事件监听启动失败 | 检查 lark-cli 配置和权限 |
| Step 8 | cron 创建失败 | 检查 Hermes 配置 |
| Step 9 | 搜索无结果 | 正常（首次可能无新增） |

## 文件索引

| 文件 | 用途 |
|------|------|
| `README.md` | 人类阅读：项目介绍和价值 |
| `SETUP.md` | Agent 阅读：初始化指南（本文件） |
| `config.json` | 用户配置 |
| `scripts/env.sh` | 全局环境变量 |
| `scripts/loop-tick.sh` | 主控循环脚本 |
| `scripts/event-listener.sh` | 飞书事件监听器 |
| `scripts/event-dispatcher.sh` | 事件分发器 |
| `scripts/01-search.sh` | Boss 直聘搜索 |
| `scripts/02-diff.sh` | 去重检测 |
| `scripts/03-check-feedback.sh` | 文档状态检测 |
| `scripts/feedback-tick.sh` | 反馈检查脚本 |
| `skills/*/SKILL.md` | Agent Skills |
| `workspace/AGENT.md` | 跨 session 上下文 |
| `workspace/preferences.json` | 偏好模型 |
| `workspace/queue.jsonl` | 任务队列 |
| `workspace/audit.jsonl` | 审计日志 |
