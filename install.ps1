<# OpenClaw Chinese Edition Installer (Windows PowerShell) #>
<# Usage: iwr -useb https://clawd.org.cn/install.ps1 | iex #>
<# 一键安装，无需任何参数 #>

param(
    [string]$Version,
    [switch]$Beta,
    [string]$Registry,
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$Help
)

# Do NOT use "Stop" - it causes the script to exit immediately on any error
$ErrorActionPreference = "Continue"

# Set UTF-8 encoding for Chinese characters
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 | Out-Null
} catch {
    # Ignore errors
}

# Colors
$AccentColor = "DarkYellow"
$InfoColor = "Yellow"
$SuccessColor = "Green"
$WarnColor = "DarkYellow"
$ErrorColor = "Red"
$MutedColor = "DarkGray"

# Show help
if ($Help) {
    Write-Host ""
    Write-Host "OpenClaw Chinese Edition Installer" -ForegroundColor $AccentColor
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor $InfoColor
    Write-Host "  iwr -useb https://clawd.org.cn/install.ps1 | iex"
    Write-Host "  .\install.ps1"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $InfoColor
    Write-Host "  -Version <version>    npm install version (default: latest)"
    Write-Host "  -Beta                 Use beta version"
    Write-Host "  -Registry <url>       npm registry (default: npmmirror)"
    Write-Host "  -DryRun               Print what would be done (no changes)"
    Write-Host "  -Verbose              Print debug output"
    Write-Host "  -Help                 Show this help"
    Write-Host ""
    exit 0
}

# Config
$script:DryRun = $DryRun -or ($env:CLAWDBOT_DRY_RUN -eq "1")
$script:Verbose = $Verbose -or ($env:CLAWDBOT_VERBOSE -eq "1")
$OpenclawVersion = if ($Version) { $Version } elseif ($env:CLAWDBOT_VERSION) { $env:CLAWDBOT_VERSION } else { "latest" }
$NpmRegistry = if ($Registry) { $Registry } elseif ($env:CLAWDBOT_NPM_REGISTRY) { $env:CLAWDBOT_NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$UseBeta = $Beta -or ($env:CLAWDBOT_BETA -eq "1")

#region ========== Default Configuration (内置默认配置) ==========

# 主配置 (moltbot.json)
$DefaultConfig = @'
{
  "meta": {
    "lastTouchedVersion": "2026.1.30"
  },
  "auth": {
    "profiles": {
      "qwen-portal:default": {
        "provider": "qwen-portal",
        "mode": "oauth"
      }
    }
  },
  "models": {
    "providers": {
      "qwen-portal": {
        "baseUrl": "https://portal.qwen.ai/v1",
        "apiKey": "qwen-oauth",
        "api": "openai-completions",
        "models": [
          {
            "id": "coder-model",
            "name": "Qwen Coder",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 128000,
            "maxTokens": 8192
          },
          {
            "id": "vision-model",
            "name": "Qwen Vision",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 128000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "qwen-portal/vision-model"
      },
      "models": {
        "qwen-portal/coder-model": { "alias": "qwen" },
        "qwen-portal/vision-model": {}
      },
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
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
        "boot-md": { "enabled": true },
        "session-memory": { "enabled": true }
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "plugins": {
    "entries": {
      "qwen-portal-auth": { "enabled": true }
    }
  }
}
'@

# 认证配置 (auth-profiles.json) - 空模板，需要用户登录
$DefaultAuthProfiles = @'
{
  "version": 1,
  "profiles": {}
}
'@

#endregion

# Refresh PATH in current session
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Check if running as Administrator
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Get npm global bin directory
function Get-NpmGlobalBin {
    try {
        $prefix = (npm config get prefix 2>$null)
        if ($prefix -and (Test-Path $prefix)) {
            return $prefix
        }
    } catch {
        # Ignore
    }
    return "$env:APPDATA\npm"
}

# Ensure npm global bin is in PATH
function Ensure-NpmInPath {
    $npmBin = Get-NpmGlobalBin
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -and $userPath.ToLower().Contains($npmBin.ToLower())) {
        return
    }
    
    Write-Host "[*] Adding npm global bin to PATH: $npmBin" -ForegroundColor $InfoColor
    
    if ($DryRun) {
        Write-Host "  [dry-run] Would add to User PATH: $npmBin" -ForegroundColor $MutedColor
    } else {
        try {
            $newPath = if ([string]::IsNullOrEmpty($userPath)) { $npmBin } else { "$userPath;$npmBin" }
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Host "[OK] npm bin added to User PATH" -ForegroundColor $SuccessColor
        } catch {
            Write-Host "[!] Failed to update PATH: $_" -ForegroundColor $WarnColor
        }
    }
    Refresh-Path
}

# Configure npm for user-level global installs
function Configure-NpmForUser {
    $npmPrefix = "$env:APPDATA\npm"
    
    if (-not (Test-Path $npmPrefix)) {
        if (-not $DryRun) {
            try {
                New-Item -ItemType Directory -Path $npmPrefix -Force | Out-Null
            } catch {
                # Ignore
            }
        }
    }
    
    if (-not $DryRun) {
        try {
            npm config set prefix "$npmPrefix" 2>$null
        } catch {
            # Ignore
        }
    }
}

# Deploy default config files
function Deploy-DefaultConfig {
    $clawdbotDir = "$env:USERPROFILE\.clawdbot"
    
    # Create directory
    if (-not (Test-Path $clawdbotDir)) {
        if ($DryRun) {
            Write-Host "  [dry-run] Would create: $clawdbotDir" -ForegroundColor $MutedColor
        } else {
            try {
                New-Item -ItemType Directory -Path $clawdbotDir -Force | Out-Null
                Write-Host "[OK] Created config directory" -ForegroundColor $SuccessColor
            } catch {
                Write-Host "[!] Failed to create config directory: $_" -ForegroundColor $ErrorColor
                return $false
            }
        }
    }
    
    # Deploy moltbot.json (only if not exists)
    $configPath = "$clawdbotDir\moltbot.json"
    if (-not (Test-Path $configPath)) {
        if ($DryRun) {
            Write-Host "  [dry-run] Would create: $configPath" -ForegroundColor $MutedColor
        } else {
            try {
                $DefaultConfig | Out-File -FilePath $configPath -Encoding UTF8
                Write-Host "[OK] Created default config: moltbot.json" -ForegroundColor $SuccessColor
            } catch {
                Write-Host "[!] Failed to create config: $_" -ForegroundColor $ErrorColor
                return $false
            }
        }
    } else {
        Write-Host "[*] Config already exists, skipping" -ForegroundColor $MutedColor
    }
    
    # Deploy auth-profiles.json (only if not exists)
    $authPath = "$clawdbotDir\auth-profiles.json"
    if (-not (Test-Path $authPath)) {
        if ($DryRun) {
            Write-Host "  [dry-run] Would create: $authPath" -ForegroundColor $MutedColor
        } else {
            try {
                $DefaultAuthProfiles | Out-File -FilePath $authPath -Encoding UTF8
                Write-Host "[OK] Created auth profiles template" -ForegroundColor $SuccessColor
            } catch {
                Write-Host "[!] Failed to create auth profiles: $_" -ForegroundColor $ErrorColor
                return $false
            }
        }
    }
    
    # Create workspace directory
    $workspaceDir = "$env:USERPROFILE\clawd"
    if (-not (Test-Path $workspaceDir)) {
        if (-not $DryRun) {
            try {
                New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null
            } catch {
                # Ignore
            }
        }
    }
    
    return $true
}

# Check Node.js installed
function Test-NodeInstalled {
    $nodeVersion = $null
    try {
        $nodeVersion = & node -v 2>&1
    } catch {
        # Ignore
    }
    
    if ($nodeVersion -and $nodeVersion -match '^v\d+') {
        $majorVersion = 0
        if ($nodeVersion -match 'v(\d+)') {
            $majorVersion = [int]$Matches[1]
        }
        if ($majorVersion -ge 22) {
            Write-Host "[OK] Node.js $nodeVersion installed" -ForegroundColor $SuccessColor
            return $true
        } else {
            Write-Host "[!] Node.js $nodeVersion found, but v22+ required" -ForegroundColor $WarnColor
            return $false
        }
    } else {
        Write-Host "[!] Node.js not found" -ForegroundColor $WarnColor
        return $false
    }
}

# Install Node.js
function Install-NodeJS {
    Write-Host "[*] Installing Node.js..." -ForegroundColor $InfoColor
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Using winget..." -ForegroundColor $MutedColor
        if (-not $DryRun) {
            & winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
            Refresh-Path
        }
        Write-Host "[OK] Node.js installed via winget" -ForegroundColor $SuccessColor
        return $true
    }
    
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Using Chocolatey..." -ForegroundColor $MutedColor
        if (-not $DryRun) {
            & choco install nodejs-lts -y
            Refresh-Path
        }
        Write-Host "[OK] Node.js installed via Chocolatey" -ForegroundColor $SuccessColor
        return $true
    }
    
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "  Using Scoop..." -ForegroundColor $MutedColor
        if (-not $DryRun) {
            & scoop install nodejs-lts
            Refresh-Path
        }
        Write-Host "[OK] Node.js installed via Scoop" -ForegroundColor $SuccessColor
        return $true
    }
    
    Write-Host ""
    Write-Host "ERROR: Cannot auto-install Node.js" -ForegroundColor $ErrorColor
    Write-Host "Please install Node.js 22+ manually: https://nodejs.org/" -ForegroundColor $InfoColor
    return $false
}

$script:IsAdmin = Test-IsAdmin

# Banner
Write-Host ""
Write-Host "  ======================================" -ForegroundColor $AccentColor
Write-Host "       OpenClaw Chinese Edition" -ForegroundColor $AccentColor
Write-Host "         一键安装 (Zero Config)" -ForegroundColor $AccentColor
Write-Host "  ======================================" -ForegroundColor $AccentColor
Write-Host ""

# OS detection
Write-Host "[OK] Windows detected" -ForegroundColor $SuccessColor

# Admin status
if ($script:IsAdmin) {
    Write-Host "[OK] Running as Administrator" -ForegroundColor $SuccessColor
} else {
    Write-Host "[*] Running as standard user" -ForegroundColor $InfoColor
    Configure-NpmForUser
}

# Check and install Node.js (auto, no prompt)
if (-not (Test-NodeInstalled)) {
    if (-not (Install-NodeJS)) {
        exit 1
    }
    if (-not (Test-NodeInstalled)) {
        Write-Host "Node.js installation failed" -ForegroundColor $ErrorColor
        exit 1
    }
}

# Install OpenClaw
$spec = "openclaw-cn"
if ($UseBeta) {
    $spec = "openclaw-cn@beta"
} elseif ($OpenclawVersion -ne "latest") {
    $spec = "openclaw-cn@$OpenclawVersion"
}

Write-Host ""
Write-Host "[*] Installing $spec..." -ForegroundColor $InfoColor
Write-Host "[*] Registry: $NpmRegistry" -ForegroundColor $MutedColor

if ($DryRun) {
    Write-Host "  [dry-run] npm install -g $spec" -ForegroundColor $MutedColor
} else {
    $npmCmd = "npm install -g `"$spec`" --no-fund --no-audit --registry `"$NpmRegistry`""
    cmd /c $npmCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: npm install failed (exit code: $LASTEXITCODE)" -ForegroundColor $ErrorColor
        exit 1
    }
    
    Write-Host "[OK] OpenClaw installed successfully" -ForegroundColor $SuccessColor
    
    if (-not $script:IsAdmin) {
        Ensure-NpmInPath
    }
    Refresh-Path
}

# Show version
Write-Host ""
$version = $null
try {
    $version = & openclaw-cn --version 2>&1
} catch {
    # Ignore
}
if ($version -and $version -notmatch 'not recognized') {
    Write-Host "[OK] Version: $version" -ForegroundColor $SuccessColor
} else {
    Write-Host "[!] Could not verify installation - restart terminal may be needed" -ForegroundColor $WarnColor
}

# Deploy default configuration (一键部署默认配置)
Write-Host ""
Write-Host "[*] Deploying default configuration..." -ForegroundColor $InfoColor
if (-not (Deploy-DefaultConfig)) {
    Write-Host "[!] Config deployment failed, but installation completed" -ForegroundColor $WarnColor
}

# Done - no onboarding wizard, config is already deployed
Write-Host ""
Write-Host "======================================" -ForegroundColor $SuccessColor
Write-Host "  Installation Complete!" -ForegroundColor $SuccessColor
Write-Host "======================================" -ForegroundColor $SuccessColor
Write-Host ""
Write-Host "Next steps:" -ForegroundColor $InfoColor
Write-Host "  1. Login to Qwen Portal: openclaw-cn models auth login --provider qwen-portal" -ForegroundColor $AccentColor
Write-Host "  2. Start Gateway:        openclaw-cn gateway" -ForegroundColor $AccentColor
Write-Host ""
Write-Host "Config location: $env:USERPROFILE\.clawdbot\" -ForegroundColor $MutedColor
Write-Host ""