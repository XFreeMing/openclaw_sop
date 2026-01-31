# Moltbot CLI 完整指南

本文档详细描述了 Moltbot 所有 CLI 命令、子命令及其参数的作用。

---

## 目录

1. [命令总览](#1-命令总览)
2. [核心概念说明](#2-核心概念说明)
3. [onboard 命令](#3-onboard-命令)
4. [gateway 命令](#4-gateway-命令)
5. [doctor 命令](#5-doctor-命令)
6. [configure 命令](#6-configure-命令)
7. [status / health / sessions 命令](#7-status--health--sessions-命令)
8. [models 命令](#8-models-命令)
9. [channels 命令](#9-channels-命令)
10. [agent / agents 命令](#10-agent--agents-命令)
11. [其他命令](#11-其他命令)
12. [维护命令](#12-维护命令)
13. [所有子 CLI 列表](#13-所有子-cli-列表)

---

## 1. 命令总览

| 命令 | 说明 | 常用场景 |
|------|------|----------|
| `onboard` | 交互式引导向导 | 首次安装、完整配置 |
| `gateway` | Gateway 控制 | 启动/停止/管理服务 |
| `doctor` | 健康检查和修复 | 故障排查 |
| `configure` | 配置向导 | 修改凭证、设备、默认值 |
| `status` | 显示渠道健康和会话 | 快速检查状态 |
| `health` | 获取 Gateway 健康 | 验证连接 |
| `sessions` | 列出会话 | 查看对话历史 |
| `models` | 模型配置 | 管理 AI 模型 |
| `channels` | 渠道管理 | 添加/删除渠道 |
| `agent` | 运行 Agent | 发送消息 |
| `agents` | 管理多 Agent | 隔离工作区 |
| `setup` | 初始化配置 | 快速初始化 |
| `dashboard` | 打开 Web UI | 可视化控制 |
| `reset` | 重置配置/状态 | 清理环境 |
| `uninstall` | 卸载服务和数据 | 完全卸载 |

---

## 2. 核心概念说明

### 2.1 绑定模式 (`--bind`)

Gateway 启动时监听的网络接口：

| 模式 | 绑定地址 | 访问范围 | 安全性 | 使用场景 |
|------|----------|----------|--------|----------|
| `loopback` | 127.0.0.1 | 仅本机 |最安全 | 默认，个人使用 |
| `lan` | 0.0.0.0 | 局域网所有设备 | 认证 | 局域网内多设备访问 |
| `tailnet` | Tailscale IP | Tailnet 设备 | ⭐⭐⭐ | 跨网络私密访问 |
| `auto` | 自动选择 | 先 loopback，失败切 lan | ⭐⭐ | 自动化部署 |
| `custom` | 自定义 IP | 自定义 | 取决于配置 | 特殊网络环境 |

**安全提示**: 
- 非 `loopback` 模式**必须**配置 Token 或密码认证
- `lan` 模式会暴露给同一网络的所有设备

### 2.2 Tailscale 模式 (`--tailscale`)

通过 Tailscale 暴露 Gateway 的方式：

| 模式 | 说明 | 访问方式 | 认证要求 |
|------|------|----------|----------|
| `off` | 禁用 | 无 | 无 |
| `serve` | Tailscale Serve | Tailnet 内 HTTPS | Token 或密码 |
| `funnel` | Tailscale Funnel | 公网 HTTPS | **强制密码认证** |

**约束规则**:
- 启用 Tailscale 时，`bind` 自动强制为 `loopback`
- `funnel` 模式强制使用密码认证（不能用 Token）

### 2.3 认证模式 (`--auth`)

Gateway 的认证方式：

| 模式 | 说明 | 配置方式 |
|------|------|----------|
| `token` | Token 认证（推荐） | `--token` 或 `gateway.auth.token` 或 `CLAWDBOT_GATEWAY_TOKEN` |
| `password` | 密码认证 | `--password` 或 `gateway.auth.password` 或 `CLAWDBOT_GATEWAY_PASSWORD` |

### 2.4 `--force` 选项

在多个命令中出现，含义略有不同：

| 命令 | `--force` 的作用 |
|------|------------------|
| `gateway` / `gateway run` | 强制杀死占用端口的进程后启动 |
| `gateway install` | 强制重新安装/覆盖已有服务 |
| `doctor` | 应用激进修复（覆盖自定义服务配置） |
| `agents delete` | 跳过确认直接删除 |

---

## 3. onboard 命令

交互式引导向导，完成 Gateway、工作空间、认证、渠道、技能的完整配置。

```bash
moltbot onboard [选项]
```

### 3.1 完整参数表

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--workspace <dir>` | string | `~/clawd` | Agent 工作空间目录 |
| `--reset` | boolean | false | 重置配置后运行向导 |
| `--non-interactive` | boolean | false | 无交互模式 |
| `--accept-risk` | boolean | false | 确认安全风险（非交互必需） |
| `--flow <flow>` | string | 交互选择 | `quickstart` / `advanced` / `manual` |
| `--mode <mode>` | string | 交互选择 | `local` / `remote` |
| `--auth-choice <choice>` | string | 交互选择 | AI 认证方式 |
| `--gateway-port <port>` | number | 18789 | Gateway 端口 |
| `--gateway-bind <mode>` | string | loopback | 网络绑定模式 |
| `--gateway-auth <mode>` | string | token | 认证模式 |
| `--gateway-token <token>` | string | 自动生成 | Gateway Token |
| `--gateway-password <pwd>` | string | - | Gateway 密码 |
| `--tailscale <mode>` | string | off | Tailscale 模式 |
| `--install-daemon` | boolean | - | 安装 Gateway 服务 |
| `--no-install-daemon` | boolean | - | 跳过服务安装 |
| `--daemon-runtime <rt>` | string | node | 服务运行时 (`node`/`bun`) |
| `--skip-channels` | boolean | false | 跳过渠道配置 |
| `--skip-skills` | boolean | false | 跳过技能配置 |
| `--skip-health` | boolean | false | 跳过健康检查 |
| `--skip-ui` | boolean | false | 跳过 UI 启动提示 |
| `--node-manager <name>` | string | 交互选择 | Node 包管理器 |
| `--json` | boolean | false | 输出 JSON 格式 |

### 3.2 认证选项 (`--auth-choice`)

| 分类 | 值 | 说明 |
|------|-----|------|
| Anthropic | `token` | setup-token（推荐） |
| | `apiKey` | API Key |
| OpenAI | `openai-codex` | ChatGPT OAuth |
| | `openai-api-key` | API Key |
| Google | `gemini-api-key` | Gemini API Key |
| | `google-antigravity` | Antigravity OAuth |
| MiniMax | `minimax-api` | MiniMax M2.1 |
| | `minimax-api-lightning` | M2.1 Lightning |
| 其他 | `openrouter-api-key` | OpenRouter |
| | `moonshot-api-key` | Moonshot AI |
| | `venice-api-key` | Venice AI |
| | `github-copilot` | GitHub Copilot |
| | `skip` | 跳过 |

### 3.3 `--install-daemon` vs `--no-install-daemon`

| 维度 | --install-daemon | --no-install-daemon |
|------|------------------|---------------------|
| Gateway 持久化 | ✅ 系统服务自动启动 | ❌ 需手动启动 |
| 重启后 | 自动运行 | 需重新启动 |
| 适用场景 | 生产环境 | 开发测试、Docker |

### 3.4 常用命令组合

```bash
# 首次快速安装
moltbot onboard --install-daemon

# 完全自定义
moltbot onboard --flow advanced --install-daemon

# 非交互式（CI/自动化）
moltbot onboard --non-interactive --accept-risk \
  --auth-choice token --token "your-token" \
  --install-daemon

# Docker 环境
moltbot onboard --no-install-daemon

# 重置后重新安装
moltbot onboard --reset --install-daemon
```

---

## 4. gateway 命令

Gateway WebSocket 服务器的控制命令。

```bash
moltbot gateway [子命令] [选项]
```

### 4.1 子命令列表

| 子命令 | 说明 |
|--------|------|
| `run` | 前台运行 Gateway |
| `status` | 显示服务状态 |
| `install` | 安装系统服务 |
| `uninstall` | 卸载系统服务 |
| `start` | 启动服务 |
| `stop` | 停止服务 |
| `restart` | 重启服务 |
| `call` | 调用 Gateway 方法 |
| `usage-cost` | 查看使用成本 |
| `health` | 获取健康状态 |
| `probe` | 探测 Gateway 可达性 |
| `discover` | 发现局域网 Gateway |

### 4.2 `gateway` / `gateway run` 参数

```bash
moltbot gateway [选项]
moltbot gateway run [选项]
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--port <port>` | number | 18789 | Gateway 端口 |
| `--bind <mode>` | string | loopback | 绑定模式 |
| `--token <token>` | string | - | Gateway Token |
| `--auth <mode>` | string | token | 认证模式 |
| `--password <pwd>` | string | - | Gateway 密码 |
| `--tailscale <mode>` | string | off | Tailscale 模式 |
| `--tailscale-reset-on-exit` | boolean | false | 退出时重置 Tailscale |
| `--allow-unconfigured` | boolean | false | 允许无配置启动 |
| `--force` | boolean | false | **强制杀死占用端口的进程** |
| `--dev` | boolean | false | 开发模式 |
| `--reset` | boolean | false | 重置开发配置（需 --dev） |
| `--verbose` | boolean | false | 详细日志 |
| `--ws-log <style>` | string | auto | WebSocket 日志样式 |
| `--compact` | boolean | false | 紧凑日志 |

**`--force` 详解**:
```bash
# 端口被占用时强制启动
moltbot gateway --force

# 工作原理：
# 1. 查找占用指定端口的进程
# 2. 先发送 SIGTERM，等待 700ms
# 3. 如果进程仍存在，发送 SIGKILL
# 4. 等待端口释放后启动 Gateway
```

### 4.3 `gateway status`

```bash
moltbot gateway status [选项]
```

| 参数 | 说明 |
|------|------|
| `--url <url>` | Gateway WebSocket URL |
| `--token <token>` | Gateway Token |
| `--password <pwd>` | Gateway 密码 |
| `--timeout <ms>` | 超时时间（默认 10000ms） |
| `--no-probe` | 跳过 RPC 探测 |
| `--deep` | 扫描系统级服务 |
| `--json` | JSON 输出 |

### 4.4 `gateway install`

```bash
moltbot gateway install [选项]
```

| 参数 | 说明 |
|------|------|
| `--port <port>` | Gateway 端口 |
| `--runtime <rt>` | 运行时 (`node`/`bun`) |
| `--token <token>` | Gateway Token |
| `--force` | 强制重新安装 |
| `--json` | JSON 输出 |

### 4.5 `gateway probe`

探测 Gateway 可达性、发现、健康和状态摘要：

```bash
moltbot gateway probe [选项]
```

| 参数 | 说明 |
|------|------|
| `--url <url>` | 显式 Gateway URL |
| `--ssh <target>` | SSH 远程隧道目标 |
| `--ssh-identity <path>` | SSH 密钥文件 |
| `--ssh-auto` | 自动从 Bonjour 发现 SSH 目标 |
| `--token <token>` | Gateway Token |
| `--password <pwd>` | Gateway 密码 |
| `--timeout <ms>` | 探测超时（默认 3000ms） |
| `--json` | JSON 输出 |

### 4.6 `gateway discover`

发现局域网和广域网的 Gateway：

```bash
moltbot gateway discover [选项]
```

| 参数 | 说明 |
|------|------|
| `--timeout <ms>` | 超时（默认 2000ms） |
| `--json` | JSON 输出 |

---

## 5. doctor 命令

健康检查和快速修复工具。

```bash
moltbot doctor [选项]
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `--yes` | boolean | 接受默认值，不提示 |
| `--repair` / `--fix` | boolean | 应用推荐修复 |
| `--force` | boolean | 激进修复（覆盖自定义配置） |
| `--non-interactive` | boolean | 无提示模式（仅安全迁移） |
| `--generate-gateway-token` | boolean | 生成并配置 Gateway Token |
| `--deep` | boolean | 扫描系统服务查找额外安装 |
| `--no-workspace-suggestions` | boolean | 禁用工作空间建议 |

**常用组合**:
```bash
# 检查问题
moltbot doctor

# 自动修复
moltbot doctor --fix

# 激进修复（覆盖配置）
moltbot doctor --force
```

---

## 6. configure 命令

交互式配置向导，用于设置凭证、设备和 Agent 默认值。

```bash
moltbot configure [选项]
```

| 参数 | 说明 |
|------|------|
| `--section <section>` | 配置特定部分（可重复） |

**可用 section**:
- `credentials` - 凭证配置
- `devices` - 设备配置
- `agents` - Agent 默认值
- `gateway` - Gateway 配置
- `channels` - 渠道配置
- `skills` - 技能配置
- `web` - Web 工具配置
- `hooks` - Hooks 配置

```bash
# 配置所有部分
moltbot configure

# 仅配置 Web 搜索
moltbot configure --section web
```

---

## 7. status / health / sessions 命令

### 7.1 status

显示渠道健康和最近会话：

```bash
moltbot status [选项]
```

| 参数 | 说明 |
|------|------|
| `--json` | JSON 输出 |
| `--all` | 完整诊断（只读） |
| `--usage` | 显示模型使用量/配额 |
| `--deep` | 探测渠道（WhatsApp、Telegram 等） |
| `--timeout <ms>` | 探测超时（默认 10000ms） |
| `--verbose` / `--debug` | 详细日志 |

### 7.2 health

获取运行中 Gateway 的健康状态：

```bash
moltbot health [选项]
```

| 参数 | 说明 |
|------|------|
| `--json` | JSON 输出 |
| `--timeout <ms>` | 超时（默认 10000ms） |
| `--verbose` / `--debug` | 详细日志 |

### 7.3 sessions

列出存储的对话会话：

```bash
moltbot sessions [选项]
```

| 参数 | 说明 |
|------|------|
| `--json` | JSON 输出 |
| `--active <minutes>` | 仅显示最近 N 分钟活跃的会话 |
| `--store <path>` | 自定义会话存储路径 |
| `--verbose` | 详细日志 |

---

## 8. models 命令

模型发现、扫描和配置。

```bash
moltbot models [子命令] [选项]
```

### 8.1 子命令列表

| 子命令 | 说明 |
|--------|------|
| `list` | 列出模型 |
| `status` | 显示配置状态 |
| `set <model>` | 设置默认模型 |
| `set-image <model>` | 设置图像模型 |
| `scan` | 扫描 OpenRouter 免费模型 |
| `aliases list/add/remove` | 管理模型别名 |
| `fallbacks list/add/remove/clear` | 管理后备模型 |
| `image-fallbacks list/add/remove/clear` | 管理图像后备模型 |
| `auth add/login/setup-token/paste-token` | 管理认证 |
| `auth order get/set/clear` | 管理认证顺序 |

### 8.2 `models list`

```bash
moltbot models list [选项]
```

| 参数 | 说明 |
|------|------|
| `--all` | 显示完整模型目录 |
| `--local` | 仅本地模型 |
| `--provider <name>` | 按 provider 过滤 |
| `--json` | JSON 输出 |
| `--plain` | 纯文本输出 |

### 8.3 `models status`

```bash
moltbot models status [选项]
```

| 参数 | 说明 |
|------|------|
| `--json` | JSON 输出 |
| `--plain` | 纯文本输出 |
| `--check` | 认证过期检查（退出码：1=过期，2=即将过期） |
| `--probe` | 实时探测认证 |
| `--probe-provider <name>` | 仅探测特定 provider |
| `--probe-timeout <ms>` | 探测超时 |

### 8.4 `models auth login`

```bash
moltbot models auth login [选项]
```

| 参数 | 说明 |
|------|------|
| `--provider <id>` | Provider ID |
| `--method <id>` | 认证方法 ID |
| `--set-default` | 应用 provider 的推荐默认模型 |

---

## 9. channels 命令

渠道管理。

```bash
moltbot channels [子命令] [选项]
```

### 9.1 子命令列表

| 子命令 | 说明 |
|--------|------|
| `list` | 列出渠道 |
| `add` | 添加渠道 |
| `remove` | 移除渠道 |
| `capabilities` | 显示渠道能力 |
| `logs` | 查看渠道日志 |
| `status` | 查看渠道状态 |
| `test` | 测试渠道 |

---

## 10. agent / agents 命令

### 10.1 agent

通过 Gateway 运行 Agent：

```bash
moltbot agent [选项]
```

| 参数 | 说明 |
|------|------|
| `-m, --message <text>` | 消息内容（必需） |
| `-t, --to <number>` | 收件人号码 |
| `--session-id <id>` | 显式会话 ID |
| `--agent <id>` | Agent ID |
| `--thinking <level>` | 思考级别（off/minimal/low/medium/high） |
| `--verbose <on/off>` | 会话详细日志 |
| `--channel <channel>` | 交付渠道 |
| `--deliver` | 发送回复到渠道 |
| `--local` | 本地运行嵌入式 Agent |
| `--json` | JSON 输出 |
| `--timeout <seconds>` | 超时（默认 600s） |

### 10.2 agents

管理隔离 Agent：

```bash
moltbot agents [子命令] [选项]
```

| 子命令 | 说明 |
|--------|------|
| `list` | 列出 Agent |
| `add [name]` | 添加 Agent |
| `set-identity` | 更新 Agent 身份 |
| `delete <id>` | 删除 Agent |

---

## 11. 其他命令

### 11.1 setup

初始化配置和工作空间：

```bash
moltbot setup [选项]
```

| 参数 | 说明 |
|------|------|
| `--workspace <dir>` | 工作空间目录 |
| `--wizard` | 运行交互式向导 |
| `--non-interactive` | 无提示模式 |
| `--mode <mode>` | 向导模式 |
| `--remote-url <url>` | 远程 Gateway URL |
| `--remote-token <token>` | 远程 Gateway Token |

### 11.2 dashboard

打开 Web 控制界面：

```bash
moltbot dashboard [选项]
```

| 参数 | 说明 |
|------|------|
| `--no-open` | 仅打印 URL，不打开浏览器 |

---

## 12. 维护命令

### 12.1 reset

重置本地配置/状态：

```bash
moltbot reset [选项]
```

| 参数 | 说明 |
|------|------|
| `--scope <scope>` | 重置范围（`config` / `config+creds+sessions` / `full`） |
| `--yes` | 跳过确认 |
| `--non-interactive` | 无提示（需 --scope + --yes） |
| `--dry-run` | 仅显示要执行的操作 |

### 12.2 uninstall

卸载服务和数据：

```bash
moltbot uninstall [选项]
```

| 参数 | 说明 |
|------|------|
| `--service` | 移除 Gateway 服务 |
| `--state` | 移除状态和配置 |
| `--workspace` | 移除工作空间 |
| `--app` | 移除 macOS 应用 |
| `--all` | 移除所有 |
| `--yes` | 跳过确认 |
| `--non-interactive` | 无提示（需 --yes） |
| `--dry-run` | 仅显示要执行的操作 |

---

## 13. 所有子 CLI 列表

以下是 Moltbot 支持的所有子命令模块：

| 命令 | 说明 |
|------|------|
| `acp` | Agent Control Protocol 工具 |
| `gateway` | Gateway 控制 |
| `daemon` | Gateway 服务（旧别名） |
| `logs` | Gateway 日志 |
| `system` | 系统事件、心跳、存在状态 |
| `models` | 模型配置 |
| `approvals` | 执行审批 |
| `nodes` | Node 命令 |
| `devices` | 设备配对和 Token 管理 |
| `node` | Node 控制 |
| `sandbox` | 沙盒工具 |
| `tui` | 终端 UI |
| `cron` | Cron 调度器 |
| `dns` | DNS 助手 |
| `docs` | 文档助手 |
| `hooks` | Hooks 工具 |
| `webhooks` | Webhook 助手 |
| `pairing` | 配对助手 |
| `plugins` | 插件管理 |
| `channels` | 渠道管理 |
| `directory` | 目录命令 |
| `security` | 安全助手 |
| `skills` | 技能管理 |
| `update` | CLI 更新助手 |

---

## 14. 配置文件位置

| 文件 | 路径 | 内容 |
|------|------|------|
| 主配置 | `~/.clawdbot/moltbot.json` | 所有配置项 |
| 工作空间 | `~/clawd/` | Agent 数据、会话 |
| 认证配置 | `~/.clawdbot/auth-profiles.json` | 认证 Profile |
| macOS 服务 | `~/Library/LaunchAgents/` | LaunchAgent plist |
| Linux 服务 | `~/.config/systemd/user/` | systemd service |

---

## 15. 故障排查

### Gateway 无法启动

```bash
# 检查端口占用
lsof -i :18789

# 强制释放端口并启动
moltbot gateway --force

# 查看服务状态
moltbot gateway status --deep
```

### 配置问题

```bash
# 运行诊断
moltbot doctor

# 自动修复
moltbot doctor --fix
```

### 认证问题

```bash
# 检查认证状态
moltbot models status --probe

# 重新配置认证
moltbot models auth login
```

---

## 16. 源码参考

| 文件 | 职责 |
|------|------|
| `src/cli/program/register.onboard.ts` | onboard 命令注册 |
| `src/cli/gateway-cli/register.ts` | gateway 命令注册 |
| `src/cli/gateway-cli/run.ts` | gateway run 实现 |
| `src/cli/program/register.maintenance.ts` | doctor/dashboard/reset/uninstall |
| `src/cli/program/register.status-health-sessions.ts` | status/health/sessions |
| `src/cli/models-cli.ts` | models 命令 |
| `src/cli/channels-cli.ts` | channels 命令 |
| `src/wizard/onboarding.ts` | onboard 向导流程 |
| `src/wizard/onboarding.finalize.ts` | 服务安装逻辑 |
