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

$ErrorActionPreference = "Continue"

# Set UTF-8 encoding
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 | Out-Null
} catch { }

# Colors
$AccentColor = "DarkYellow"
$InfoColor = "Yellow"
$SuccessColor = "Green"
$WarnColor = "DarkYellow"
$ErrorColor = "Red"
$MutedColor = "DarkGray"

# Help
if ($Help) {
    Write-Host ""
    Write-Host "OpenClaw Chinese Edition - One-Click Installer" -ForegroundColor $AccentColor
    Write-Host ""
    Write-Host "Usage: .\install.ps1"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Version <version>  npm version (default: latest)"
    Write-Host "  -Beta               Use beta version"
    Write-Host "  -Registry <url>     npm registry"
    Write-Host "  -DryRun             Print actions only"
    Write-Host "  -Verbose            Debug output"
    Write-Host ""
    exit 0
}

# Config
$script:DryRun = $DryRun -or ($env:CLAWDBOT_DRY_RUN -eq "1")
$script:Verbose = $Verbose -or ($env:CLAWDBOT_VERBOSE -eq "1")
$OpenclawVersion = if ($Version) { $Version } elseif ($env:CLAWDBOT_VERSION) { $env:CLAWDBOT_VERSION } else { "latest" }
$NpmRegistry = if ($Registry) { $Registry } elseif ($env:CLAWDBOT_NPM_REGISTRY) { $env:CLAWDBOT_NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$UseBeta = $Beta -or ($env:CLAWDBOT_BETA -eq "1")

#region ========== JSON Config Patches (配置补丁) ==========

# Models config patch - add qwen-portal provider
$ModelsPatch = @'
{
  "providers": {
    "qwen-portal": {
      "baseUrl": "https://portal.qwen.ai/v1",
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
      ],
      "apiKey": "qwen-oauth"
    }
  }
}
'@

# Auth profiles patch - for qwen-portal OAuth
$AuthProfilesPatch = @'
{
  "version": 1,
  "profiles": {
    "qwen-portal:default": {
      "type": "oauth",
      "provider": "qwen-portal"
    }
  }
}
'@

#endregion

#region ========== Helper Functions ==========

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NpmGlobalBin {
    try {
        $prefix = (npm config get prefix 2>$null)
        if ($prefix -and (Test-Path $prefix)) { return $prefix }
    } catch { }
    return "$env:APPDATA\npm"
}

function Ensure-NpmInPath {
    $npmBin = Get-NpmGlobalBin
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -and $userPath.ToLower().Contains($npmBin.ToLower())) { return }
    
    Write-Host "[*] Adding npm bin to PATH" -ForegroundColor $InfoColor
    if (-not $DryRun) {
        try {
            $newPath = if ([string]::IsNullOrEmpty($userPath)) { $npmBin } else { "$userPath;$npmBin" }
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        } catch { }
    }
    Refresh-Path
}

function Configure-NpmForUser {
    $npmPrefix = "$env:APPDATA\npm"
    if (-not (Test-Path $npmPrefix) -and -not $DryRun) {
        try { New-Item -ItemType Directory -Path $npmPrefix -Force | Out-Null } catch { }
    }
    if (-not $DryRun) {
        try { npm config set prefix "$npmPrefix" 2>$null } catch { }
    }
}

function Test-NodeInstalled {
    try {
        $nodeVersion = & node -v 2>&1
        if ($nodeVersion -and $nodeVersion -match '^v(\d+)') {
            if ([int]$Matches[1] -ge 22) {
                Write-Host "[OK] Node.js $nodeVersion" -ForegroundColor $SuccessColor
                return $true
            }
            Write-Host "[!] Node.js $nodeVersion found, v22+ required" -ForegroundColor $WarnColor
        }
    } catch { }
    Write-Host "[!] Node.js not found" -ForegroundColor $WarnColor
    return $false
}

function Install-NodeJS {
    Write-Host "[*] Installing Node.js..." -ForegroundColor $InfoColor
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            & winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
            Refresh-Path
        }
        return $true
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        if (-not $DryRun) { & choco install nodejs-lts -y; Refresh-Path }
        return $true
    }
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        if (-not $DryRun) { & scoop install nodejs-lts; Refresh-Path }
        return $true
    }
    
    Write-Host "ERROR: Cannot auto-install Node.js. Please install manually: https://nodejs.org/" -ForegroundColor $ErrorColor
    return $false
}

# Update JSON file by merging patch into existing file
function Update-JsonFile {
    param(
        [string]$FilePath,
        [string]$PatchJson,
        [string]$Description
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "[!] File not found: $FilePath" -ForegroundColor $WarnColor
        return $false
    }
    
    if ($DryRun) {
        Write-Host "  [dry-run] Would update: $FilePath" -ForegroundColor $MutedColor
        return $true
    }
    
    try {
        # Read existing file
        $existingContent = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $existingObj = $existingContent | ConvertFrom-Json
        
        # Parse patch
        $patchObj = $PatchJson | ConvertFrom-Json
        
        # Deep merge - add patch properties to existing
        foreach ($prop in $patchObj.PSObject.Properties) {
            $propName = $prop.Name
            $propValue = $prop.Value
            
            if ($existingObj.PSObject.Properties[$propName]) {
                # Property exists - merge if it's an object
                if ($propValue -is [PSCustomObject] -and $existingObj.$propName -is [PSCustomObject]) {
                    foreach ($subProp in $propValue.PSObject.Properties) {
                        $existingObj.$propName | Add-Member -NotePropertyName $subProp.Name -NotePropertyValue $subProp.Value -Force
                    }
                } else {
                    $existingObj.$propName = $propValue
                }
            } else {
                # Property doesn't exist - add it
                $existingObj | Add-Member -NotePropertyName $propName -NotePropertyValue $propValue -Force
            }
        }
        
        # Write back
        $existingObj | ConvertTo-Json -Depth 20 | Out-File -FilePath $FilePath -Encoding UTF8
        Write-Host "[OK] Updated: $Description" -ForegroundColor $SuccessColor
        return $true
    } catch {
        Write-Host "[!] Failed to update $FilePath : $_" -ForegroundColor $ErrorColor
        return $false
    }
}

#endregion

$script:IsAdmin = Test-IsAdmin

# Banner
Write-Host ""
Write-Host "  ======================================" -ForegroundColor $AccentColor
Write-Host "       OpenClaw Chinese Edition" -ForegroundColor $AccentColor
Write-Host "         一键安装 (One-Click)" -ForegroundColor $AccentColor
Write-Host "  ======================================" -ForegroundColor $AccentColor
Write-Host ""

Write-Host "[OK] Windows detected" -ForegroundColor $SuccessColor

if ($script:IsAdmin) {
    Write-Host "[OK] Running as Administrator" -ForegroundColor $SuccessColor
} else {
    Write-Host "[*] Running as standard user" -ForegroundColor $InfoColor
    Configure-NpmForUser
}

# Install Node.js if needed
if (-not (Test-NodeInstalled)) {
    if (-not (Install-NodeJS)) { exit 1 }
    if (-not (Test-NodeInstalled)) {
        Write-Host "Node.js installation failed" -ForegroundColor $ErrorColor
        exit 1
    }
}

# Install OpenClaw
$spec = "openclaw-cn"
if ($UseBeta) { $spec = "openclaw-cn@beta" }
elseif ($OpenclawVersion -ne "latest") { $spec = "openclaw-cn@$OpenclawVersion" }

Write-Host ""
Write-Host "[*] Installing $spec..." -ForegroundColor $InfoColor

if ($DryRun) {
    Write-Host "  [dry-run] npm install -g $spec" -ForegroundColor $MutedColor
} else {
    $npmCmd = "npm install -g `"$spec`" --no-fund --no-audit --registry `"$NpmRegistry`""
    cmd /c $npmCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: npm install failed" -ForegroundColor $ErrorColor
        exit 1
    }
    
    Write-Host "[OK] OpenClaw installed" -ForegroundColor $SuccessColor
    if (-not $script:IsAdmin) { Ensure-NpmInPath }
    Refresh-Path
}

# Verify installation
$version = $null
try { $version = & openclaw-cn --version 2>&1 } catch { }
if ($version -and $version -notmatch 'not recognized') {
    Write-Host "[OK] Version: $version" -ForegroundColor $SuccessColor
}

# ========== Step 1: Run onboard --non-interactive to initialize .clawdbot ==========
Write-Host ""
Write-Host "[*] Initializing configuration (onboard --non-interactive)..." -ForegroundColor $InfoColor

if ($DryRun) {
    Write-Host "  [dry-run] openclaw-cn onboard --non-interactive ..." -ForegroundColor $MutedColor
} else {
    $onboardArgs = @(
        "onboard",
        "--non-interactive",
        "--accept-risk",
        "--mode", "local",
        "--auth-choice", "skip",           # Skip auth for now, will patch later
        "--gateway-port", "18789",
        "--gateway-bind", "loopback",
        "--install-daemon",
        "--daemon-runtime", "node",
        "--skip-channels",
        "--skip-skills",
        "--skip-health",
        "--skip-ui"
    )
    
    if ($script:Verbose) {
        Write-Host "  [debug] openclaw-cn $($onboardArgs -join ' ')" -ForegroundColor $MutedColor
    }
    
    & openclaw-cn @onboardArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Onboard returned non-zero exit code, continuing..." -ForegroundColor $WarnColor
    } else {
        Write-Host "[OK] Configuration initialized" -ForegroundColor $SuccessColor
    }
}

# ========== Step 2: Patch JSON config files with qwen-portal settings ==========
Write-Host ""
Write-Host "[*] Patching configuration for Qwen Portal..." -ForegroundColor $InfoColor

$clawdbotDir = "$env:USERPROFILE\.clawdbot"

# Update moltbot.json with models config
$moltbotJson = "$clawdbotDir\moltbot.json"
if (Test-Path $moltbotJson) {
    if (-not $DryRun) {
        try {
            $config = Get-Content -Path $moltbotJson -Raw -Encoding UTF8 | ConvertFrom-Json
            
            # Add models.providers.qwen-portal
            $modelsObj = $ModelsPatch | ConvertFrom-Json
            if (-not $config.models) {
                $config | Add-Member -NotePropertyName "models" -NotePropertyValue @{} -Force
            }
            if (-not $config.models.providers) {
                $config.models | Add-Member -NotePropertyName "providers" -NotePropertyValue @{} -Force
            }
            $config.models.providers | Add-Member -NotePropertyName "qwen-portal" -NotePropertyValue $modelsObj.providers.'qwen-portal' -Force
            
            # Add auth.profiles for qwen-portal
            if (-not $config.auth) {
                $config | Add-Member -NotePropertyName "auth" -NotePropertyValue @{} -Force
            }
            if (-not $config.auth.profiles) {
                $config.auth | Add-Member -NotePropertyName "profiles" -NotePropertyValue @{} -Force
            }
            $config.auth.profiles | Add-Member -NotePropertyName "qwen-portal:default" -NotePropertyValue @{
                provider = "qwen-portal"
                mode = "oauth"
            } -Force
            
            # Set default model
            if (-not $config.agents) {
                $config | Add-Member -NotePropertyName "agents" -NotePropertyValue @{} -Force
            }
            if (-not $config.agents.defaults) {
                $config.agents | Add-Member -NotePropertyName "defaults" -NotePropertyValue @{} -Force
            }
            if (-not $config.agents.defaults.model) {
                $config.agents.defaults | Add-Member -NotePropertyName "model" -NotePropertyValue @{} -Force
            }
            $config.agents.defaults.model | Add-Member -NotePropertyName "primary" -NotePropertyValue "qwen-portal/vision-model" -Force
            
            # Add plugins
            if (-not $config.plugins) {
                $config | Add-Member -NotePropertyName "plugins" -NotePropertyValue @{} -Force
            }
            if (-not $config.plugins.entries) {
                $config.plugins | Add-Member -NotePropertyName "entries" -NotePropertyValue @{} -Force
            }
            $config.plugins.entries | Add-Member -NotePropertyName "qwen-portal-auth" -NotePropertyValue @{ enabled = $true } -Force
            
            # Write back
            $config | ConvertTo-Json -Depth 20 | Out-File -FilePath $moltbotJson -Encoding UTF8
            Write-Host "[OK] Updated moltbot.json with Qwen Portal config" -ForegroundColor $SuccessColor
        } catch {
            Write-Host "[!] Failed to patch moltbot.json: $_" -ForegroundColor $WarnColor
        }
    }
} else {
    Write-Host "[!] moltbot.json not found, skip patching" -ForegroundColor $WarnColor
}

# Update auth-profiles.json
$authProfilesJson = "$clawdbotDir\auth-profiles.json"
if (Test-Path $authProfilesJson) {
    if (-not $DryRun) {
        try {
            $authConfig = Get-Content -Path $authProfilesJson -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $authConfig.profiles) {
                $authConfig | Add-Member -NotePropertyName "profiles" -NotePropertyValue @{} -Force
            }
            $authConfig.profiles | Add-Member -NotePropertyName "qwen-portal:default" -NotePropertyValue @{
                type = "oauth"
                provider = "qwen-portal"
            } -Force
            
            $authConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $authProfilesJson -Encoding UTF8
            Write-Host "[OK] Updated auth-profiles.json" -ForegroundColor $SuccessColor
        } catch {
            Write-Host "[!] Failed to patch auth-profiles.json: $_" -ForegroundColor $WarnColor
        }
    }
} else {
    Write-Host "[!] auth-profiles.json not found, skip patching" -ForegroundColor $WarnColor
}

# Done
Write-Host ""
Write-Host "======================================" -ForegroundColor $SuccessColor
Write-Host "  Installation Complete!" -ForegroundColor $SuccessColor
Write-Host "======================================" -ForegroundColor $SuccessColor
Write-Host ""
Write-Host "Next step - Login to Qwen Portal:" -ForegroundColor $InfoColor
Write-Host "  openclaw-cn models auth login --provider qwen-portal" -ForegroundColor $AccentColor
Write-Host ""
Write-Host "Then start Gateway:" -ForegroundColor $InfoColor
Write-Host "  openclaw-cn gateway" -ForegroundColor $AccentColor
Write-Host ""