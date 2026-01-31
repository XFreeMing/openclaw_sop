#!/bin/bash
#
# Moltbot 一键配置启动脚本
# 功能: 直接修改配置文件并启动 Gateway，无需交互式向导
#
# 使用方法:
#   chmod +x moltbot-quick-setup.sh
#   ./moltbot-quick-setup.sh [选项]
#
# 选项:
#   --auth-choice    认证方式 (google-antigravity, token, apiKey, openai-codex, etc.)
#   --model          默认模型 (如 google-antigravity/claude-opus-4-5-thinking)
#   --port           Gateway 端口 (默认: 18789)
#   --bind           绑定模式 (loopback, lan, tailnet, auto, custom)
#   --workspace      工作空间目录 (默认: ~/clawd)
#   --install-daemon 安装为系统服务
#   --force          强制覆盖现有配置
#   --help           显示帮助
#

set -e

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === 默认配置 ===
CONFIG_DIR="$HOME/.clawdbot"
CONFIG_FILE="$CONFIG_DIR/moltbot.json"
DEFAULT_PORT=18789
DEFAULT_BIND="loopback"
DEFAULT_WORKSPACE="$HOME/clawd"
DEFAULT_AUTH_MODE="token"

# === 参数变量 ===
AUTH_CHOICE=""
MODEL=""
PORT=""
BIND=""
WORKSPACE=""
GATEWAY_TOKEN=""
INSTALL_DAEMON=false
FORCE=false
START_GATEWAY=true

# === 函数定义 ===

print_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════╗"
    echo "║     Moltbot 一键配置启动脚本           ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_help() {
    cat << EOF
Moltbot 一键配置启动脚本

使用方法:
  $0 [选项]

选项:
  --auth-choice <choice>   认证方式:
                           - google-antigravity  Google Antigravity OAuth
                           - token               Anthropic setup-token
                           - apiKey              Anthropic API Key
                           - openai-codex        ChatGPT OAuth
                           - openai-api-key      OpenAI API Key
                           - gemini-api-key      Google Gemini API Key
                           - openrouter-api-key  OpenRouter API Key
                           - github-copilot      GitHub Copilot
                           - skip                跳过认证配置

  --model <model>          默认模型 ID (如 google-antigravity/claude-opus-4-5-thinking)
  --port <port>            Gateway 端口 (默认: 18789)
  --bind <mode>            绑定模式:
                           - loopback  仅本机 (默认, 最安全)
                           - lan       局域网 (需认证)
                           - tailnet   Tailscale 网络
                           - auto      自动选择
                           - custom    自定义

  --workspace <dir>        工作空间目录 (默认: ~/clawd)
  --token <token>          Gateway Token (不指定则自动生成)
  --install-daemon         安装为系统服务 (开机自启)
  --no-start               只配置不启动
  --force                  强制覆盖现有配置
  --help                   显示此帮助

示例:
  # 使用 Google Antigravity，安装为服务
  $0 --auth-choice google-antigravity --install-daemon

  # 自定义端口，局域网访问
  $0 --port 8080 --bind lan --token "your-secure-token"

  # 使用 OpenAI，指定模型
  $0 --auth-choice openai-api-key --model openai/gpt-4o

  # 仅生成配置，不启动
  $0 --auth-choice token --no-start

EOF
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

generate_token() {
    # 生成 24 字节的随机 token (48 字符 hex)
    if command -v openssl &> /dev/null; then
        openssl rand -hex 24
    elif command -v xxd &> /dev/null; then
        head -c 24 /dev/urandom | xxd -p
    else
        # 回退到 $RANDOM
        echo "$(date +%s%N)$(($RANDOM * $RANDOM))" | sha256sum | head -c 48
    fi
}

check_dependencies() {
    log_info "检查依赖..."
    
    # 检查 jq
    if ! command -v jq &> /dev/null; then
        log_error "需要 jq 来处理 JSON。请安装: brew install jq 或 apt install jq"
        exit 1
    fi
    
    # 检查 moltbot
    if ! command -v moltbot &> /dev/null; then
        log_warn "未找到 moltbot 命令，将使用 npm run 方式"
        MOLTBOT_CMD="npm run --prefix $HOME/workspace/boltbot -- moltbot"
    else
        MOLTBOT_CMD="moltbot"
    fi
}

create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        log_info "创建配置目录: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR"
    fi
}

create_workspace_dir() {
    local ws="${WORKSPACE:-$DEFAULT_WORKSPACE}"
    if [ ! -d "$ws" ]; then
        log_info "创建工作空间目录: $ws"
        mkdir -p "$ws"
    fi
}

backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        local backup="$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "备份现有配置到: $backup"
        cp "$CONFIG_FILE" "$backup"
    fi
}

generate_config() {
    local port="${PORT:-$DEFAULT_PORT}"
    local bind="${BIND:-$DEFAULT_BIND}"
    local workspace="${WORKSPACE:-$DEFAULT_WORKSPACE}"
    local token="${GATEWAY_TOKEN:-$(generate_token)}"
    local model="${MODEL:-}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    
    log_info "生成配置文件..."
    log_info "  端口: $port"
    log_info "  绑定: $bind"
    log_info "  工作空间: $workspace"
    log_info "  Token: ${token:0:8}..."
    
    # 构建基础配置
    local config=$(cat << EOF
{
  "meta": {
    "lastTouchedVersion": "script-generated",
    "lastTouchedAt": "$timestamp"
  },
  "wizard": {
    "lastRunAt": "$timestamp",
    "lastRunVersion": "script-generated",
    "lastRunCommand": "quick-setup",
    "lastRunMode": "local"
  },
  "agents": {
    "defaults": {
      "workspace": "$workspace",
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "boot-md": {
          "enabled": true
        }
      }
    }
  },
  "gateway": {
    "port": $port,
    "mode": "local",
    "bind": "$bind",
    "auth": {
      "mode": "token",
      "token": "$token"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "skills": {
    "install": {
      "nodeManager": "pnpm"
    }
  }
}
EOF
)

    # 如果指定了模型，添加模型配置
    if [ -n "$model" ]; then
        config=$(echo "$config" | jq --arg model "$model" '.agents.defaults.model = {"primary": $model} | .agents.defaults.models = {($model): {}}')
    fi
    
    # 根据认证选择添加认证配置
    case "$AUTH_CHOICE" in
        google-antigravity)
            config=$(echo "$config" | jq '.plugins.entries["google-antigravity-auth"] = {"enabled": true}')
            log_info "已启用 Google Antigravity 认证插件"
            ;;
        openrouter-api-key)
            log_warn "请设置环境变量 OPENROUTER_API_KEY"
            ;;
        openai-api-key)
            log_warn "请设置环境变量 OPENAI_API_KEY"
            ;;
        gemini-api-key)
            log_warn "请设置环境变量 GOOGLE_GENERATIVE_AI_API_KEY"
            ;;
    esac
    
    echo "$config" > "$CONFIG_FILE"
    log_info "配置已写入: $CONFIG_FILE"
    
    # 保存 token 用于后续显示
    echo "$token" > "$CONFIG_DIR/.last-token"
}

merge_config() {
    # 如果已有配置，合并而不是覆盖
    local port="${PORT:-$DEFAULT_PORT}"
    local bind="${BIND:-$DEFAULT_BIND}"
    local workspace="${WORKSPACE:-$DEFAULT_WORKSPACE}"
    local token="${GATEWAY_TOKEN:-$(generate_token)}"
    
    log_info "合并配置..."
    
    local current=$(cat "$CONFIG_FILE")
    local updated=$(echo "$current" | jq \
        --argjson port "$port" \
        --arg bind "$bind" \
        --arg workspace "$workspace" \
        --arg token "$token" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")" \
        '
        .gateway.port = $port |
        .gateway.bind = $bind |
        .gateway.mode = "local" |
        .gateway.auth.mode = "token" |
        .gateway.auth.token = $token |
        .agents.defaults.workspace = $workspace |
        .meta.lastTouchedAt = $timestamp
        ')
    
    echo "$updated" > "$CONFIG_FILE"
    echo "$token" > "$CONFIG_DIR/.last-token"
    log_info "配置已更新"
}

install_daemon() {
    log_info "安装 Gateway 系统服务..."
    
    local port="${PORT:-$DEFAULT_PORT}"
    local token=$(cat "$CONFIG_DIR/.last-token" 2>/dev/null || echo "")
    
    $MOLTBOT_CMD gateway install --port "$port" ${token:+--token "$token"} --force
    
    if [ $? -eq 0 ]; then
        log_info "服务安装成功"
    else
        log_error "服务安装失败"
        exit 1
    fi
}

start_gateway() {
    log_info "启动 Gateway..."
    
    local port="${PORT:-$DEFAULT_PORT}"
    
    # 先检查是否已有服务运行
    if $MOLTBOT_CMD gateway status --no-probe &> /dev/null; then
        log_info "Gateway 服务已在运行，执行重启..."
        $MOLTBOT_CMD gateway restart
    else
        # 非服务模式，前台启动
        log_info "以服务模式启动..."
        $MOLTBOT_CMD gateway start || {
            log_warn "服务启动失败，尝试安装后启动..."
            install_daemon
            $MOLTBOT_CMD gateway start
        }
    fi
}

run_health_check() {
    log_info "执行健康检查..."
    sleep 2
    
    local port="${PORT:-$DEFAULT_PORT}"
    
    if $MOLTBOT_CMD health --timeout 5000 &> /dev/null; then
        log_info "✅ Gateway 健康检查通过"
    else
        log_warn "⚠️ 健康检查未通过，Gateway 可能仍在启动中"
    fi
}

print_summary() {
    local port="${PORT:-$DEFAULT_PORT}"
    local token=$(cat "$CONFIG_DIR/.last-token" 2>/dev/null || echo "未知")
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}配置完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "Gateway 地址: ws://localhost:$port"
    echo "Gateway Token: $token"
    echo ""
    echo "常用命令:"
    echo "  moltbot status          # 查看状态"
    echo "  moltbot health          # 健康检查"
    echo "  moltbot gateway stop    # 停止服务"
    echo "  moltbot gateway restart # 重启服务"
    echo "  moltbot dashboard       # 打开控制面板"
    echo ""
    
    if [ -n "$AUTH_CHOICE" ] && [ "$AUTH_CHOICE" != "skip" ]; then
        echo -e "${YELLOW}提示: 如需完成认证配置，请运行:${NC}"
        echo "  moltbot models auth login"
        echo ""
    fi
}

# === 参数解析 ===

while [[ $# -gt 0 ]]; do
    case $1 in
        --auth-choice)
            AUTH_CHOICE="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --bind)
            BIND="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --token)
            GATEWAY_TOKEN="$2"
            shift 2
            ;;
        --install-daemon)
            INSTALL_DAEMON=true
            shift
            ;;
        --no-start)
            START_GATEWAY=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            print_help
            ;;
        *)
            log_error "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

# === 主流程 ===

print_banner
check_dependencies
create_config_dir
create_workspace_dir

# 检查现有配置
if [ -f "$CONFIG_FILE" ]; then
    if [ "$FORCE" = true ]; then
        backup_config
        generate_config
    else
        log_info "发现现有配置，执行合并更新"
        merge_config
    fi
else
    generate_config
fi

# 安装服务
if [ "$INSTALL_DAEMON" = true ]; then
    install_daemon
fi

# 启动 Gateway
if [ "$START_GATEWAY" = true ]; then
    start_gateway
    run_health_check
fi

print_summary
