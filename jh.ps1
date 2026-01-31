<# OpenClaw Chinese Edition Installer (Windows PowerShell) #>
<# Usage: iwr -useb https://clawd.org.cn/install.ps1 | iex #>
<# Usage with registry: .\install.ps1 -Registry https://registry.npmmirror.com #>

param(
    [string]$Version,
    [switch]$Beta,
    [string]$Registry,
    [switch]$NoOnboard,
    [switch]$NoPrompt,
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$Help
)

# Do NOT use "Stop" - it causes the script to exit immediately on any error
$ErrorActionPreference = "Continue"

# Set UTF-8 encoding for Chinese characters in moltbot-cn output
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # Set code page to UTF-8
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
    Write-Host "  .\install.ps1 [options]"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $InfoColor
    Write-Host "  -Version <version>    npm install version (default: latest)"
    Write-Host "  -Beta                 Use beta version (if available)"
    Write-Host "  -Registry <url>       npm registry (default: https://registry.npmmirror.com)"
    Write-Host "  -NoOnboard            Skip onboarding (non-interactive)"
    Write-Host "  -NoPrompt             Disable prompts (required for CI/automation)"
    Write-Host "  -DryRun               Print what would be done (no changes)"
    Write-Host "  -Verbose              Print debug output"
    Write-Host "  -Help                 Show this help"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor $InfoColor
    Write-Host "  iwr -useb https://clawd.org.cn/install.ps1 | iex"
    Write-Host "  .\install.ps1 -Registry https://registry.npmmirror.com"
    Write-Host "  .\install.ps1 -Version 1.0.0 -NoOnboard"
    Write-Host ""
    exit 0
}

# Config - CLI args override env vars
$script:NoOnboard = $NoOnboard -or ($env:CLAWDBOT_NO_ONBOARD -eq "1")
$script:NoPrompt = $NoPrompt -or ($env:CLAWDBOT_NO_PROMPT -eq "1")
$script:DryRun = $DryRun -or ($env:CLAWDBOT_DRY_RUN -eq "1")
$OpenclawVersion = if ($Version) { $Version } elseif ($env:CLAWDBOT_VERSION) { $env:CLAWDBOT_VERSION } else { "latest" }
$NpmRegistry = if ($Registry) { $Registry } elseif ($env:CLAWDBOT_NPM_REGISTRY) { $env:CLAWDBOT_NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$UseBeta = $Beta -or ($env:CLAWDBOT_BETA -eq "1")
$script:Verbose = $Verbose -or ($env:CLAWDBOT_VERBOSE -eq "1")

# Refresh PATH in current session (User PATH first, then Machine PATH)
function Refresh-Path {
    # User PATH should come FIRST so user-installed tools take priority over system-installed ones
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($userPath) {
        $env:Path = "$userPath;$machinePath"
    } else {
        $env:Path = $machinePath
    }
}

# Prioritize user-installed Node.js over global installation
# This is critical for sub-accounts that need to use their own Node.js
function Prioritize-UserNode {
    $userNodePath = "$env:LOCALAPPDATA\Programs\nodejs"
    
    # Check if user Node.js exists
    if (-not (Test-Path "$userNodePath\node.exe")) {
        if ($script:Verbose) {
            Write-Host "  [debug] User Node.js not found at: $userNodePath" -ForegroundColor $MutedColor
        }
        return $false
    }
    
    Write-Host "[*] Found user Node.js at: $userNodePath" -ForegroundColor $InfoColor
    
    # Ensure user Node.js path is at the FRONT of user PATH
    $userEnvPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    # Remove any existing reference to user Node.js path (to avoid duplicates)
    if ($userEnvPath) {
        $pathArray = $userEnvPath -split ";" | Where-Object { $_.ToLower().Trim() -ne $userNodePath.ToLower() -and $_ -ne "" }
        $userEnvPath = $pathArray -join ";"
    }
    
    # Add user Node.js path to the front
    $newUserPath = if ($userEnvPath) { "$userNodePath;$userEnvPath" } else { $userNodePath }
    
    try {
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Host "[OK] User Node.js prioritized in PATH" -ForegroundColor $SuccessColor
    } catch {
        Write-Host "[!] Failed to update PATH, using temporary override" -ForegroundColor $WarnColor
    }
    
    # Also update current session immediately
    $env:Path = "$userNodePath;$env:Path"
    
    if ($script:Verbose) {
        Write-Host "  [debug] Current node: $(where.exe node 2>$null | Select-Object -First 1)" -ForegroundColor $MutedColor
    }
    
    return $true
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
    # Default fallback
    return "$env:APPDATA\npm"
}

# Ensure npm global bin is in PATH (for non-admin users)
function Ensure-NpmInPath {
    $npmBin = Get-NpmGlobalBin
    
    # Check if already in PATH
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -and $userPath.ToLower().Contains($npmBin.ToLower())) {
        if ($script:Verbose) {
            Write-Host "  [debug] npm bin already in PATH: $npmBin" -ForegroundColor $MutedColor
        }
        return
    }
    
    # Add to user PATH
    Write-Host "[*] Adding npm global bin to PATH: $npmBin" -ForegroundColor $InfoColor
    
    if ($DryRun) {
        Write-Host "  [dry-run] Would add to User PATH: $npmBin" -ForegroundColor $MutedColor
    } else {
        try {
            if ([string]::IsNullOrEmpty($userPath)) {
                $newPath = $npmBin
            } else {
                $newPath = "$userPath;$npmBin"
            }
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Host "[OK] npm bin added to User PATH" -ForegroundColor $SuccessColor
        } catch {
            Write-Host "[!] Failed to update PATH: $_" -ForegroundColor $WarnColor
            Write-Host "  You may need to manually add this to your PATH: $npmBin" -ForegroundColor $InfoColor
        }
    }
    
    # Refresh current session
    Refresh-Path
}

# Configure npm for user-level global installs (non-admin)
function Configure-NpmForUser {
    $npmPrefix = "$env:APPDATA\npm"
    
    # Ensure the directory exists
    if (-not (Test-Path $npmPrefix)) {
        if ($DryRun) {
            Write-Host "  [dry-run] Would create directory: $npmPrefix" -ForegroundColor $MutedColor
        } else {
            try {
                New-Item -ItemType Directory -Path $npmPrefix -Force | Out-Null
            } catch {
                Write-Host "[!] Failed to create npm directory: $_" -ForegroundColor $WarnColor
            }
        }
    }
    
    # Set npm prefix to user directory
    if ($DryRun) {
        Write-Host "  [dry-run] Would set npm prefix: $npmPrefix" -ForegroundColor $MutedColor
        Write-Host "  [dry-run] Would set npm registry: $NpmRegistry" -ForegroundColor $MutedColor
    } else {
        try {
            npm config set prefix "$npmPrefix" 2>$null
            if ($script:Verbose) {
                Write-Host "  [debug] npm prefix set to: $npmPrefix" -ForegroundColor $MutedColor
            }
        } catch {
            # Ignore - npm will use default
        }
        
        # Set npm registry to ensure using the correct mirror
        try {
            npm config set registry "$NpmRegistry" 2>$null
            Write-Host "[OK] npm registry set to: $NpmRegistry" -ForegroundColor $SuccessColor
        } catch {
            Write-Host "[!] Failed to set npm registry" -ForegroundColor $WarnColor
        }
    }
}

# Store admin status
$script:IsAdmin = Test-IsAdmin

# Banner
Write-Host ""
Write-Host "  ======================================" -ForegroundColor $AccentColor
Write-Host "       OpenClaw Chinese Edition" -ForegroundColor $AccentColor
Write-Host "  ======================================" -ForegroundColor $AccentColor
Write-Host ""

# Detect OS
Write-Host "[OK] Windows detected" -ForegroundColor $SuccessColor

# Show admin status and configure for non-admin
if ($script:IsAdmin) {
    Write-Host "[OK] Running as Administrator" -ForegroundColor $SuccessColor
} else {
    Write-Host "[*] Running as standard user (non-admin)" -ForegroundColor $InfoColor
    Write-Host "  Will install to user directory: $env:APPDATA\npm" -ForegroundColor $MutedColor
    
    # Prioritize user Node.js over global installation (critical for sub-accounts)
    Prioritize-UserNode | Out-Null
    
    Configure-NpmForUser
}

# Check Node.js
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
            Write-Host "[!] Node.js $nodeVersion installed, but v22+ required" -ForegroundColor $WarnColor
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
        if ($DryRun) {
            Write-Host "  [dry-run] winget install OpenJS.NodeJS.LTS" -ForegroundColor $MutedColor
        } else {
            & winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
            Refresh-Path
        }
        Write-Host "[OK] Node.js installed via winget" -ForegroundColor $SuccessColor
        return $true
    }
    
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Using Chocolatey..." -ForegroundColor $MutedColor
        if ($DryRun) {
            Write-Host "  [dry-run] choco install nodejs-lts -y" -ForegroundColor $MutedColor
        } else {
            & choco install nodejs-lts -y
            Refresh-Path
        }
        Write-Host "[OK] Node.js installed via Chocolatey" -ForegroundColor $SuccessColor
        return $true
    }
    
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "  Using Scoop..." -ForegroundColor $MutedColor
        if ($DryRun) {
            Write-Host "  [dry-run] scoop install nodejs-lts" -ForegroundColor $MutedColor
        } else {
            & scoop install nodejs-lts
            Refresh-Path
        }
        Write-Host "[OK] Node.js installed via Scoop" -ForegroundColor $SuccessColor
        return $true
    }
    
    Write-Host ""
    Write-Host "ERROR: Cannot auto-install Node.js" -ForegroundColor $ErrorColor
    Write-Host ""
    Write-Host "Please install Node.js 22+ manually:" -ForegroundColor $InfoColor
    Write-Host "  https://nodejs.org/en/download/" -ForegroundColor $AccentColor
    Write-Host ""
    return $false
}

# Check and install Node.js
if (-not (Test-NodeInstalled)) {
    if ($NoPrompt) {
        if (-not (Install-NodeJS)) {
            exit 1
        }
    } else {
        Write-Host ""
        $response = Read-Host "Install Node.js? [Y/n]"
        if ([string]::IsNullOrEmpty($response) -or $response -match '^[Yy]') {
            if (-not (Install-NodeJS)) {
                exit 1
            }
        } else {
            Write-Host "Node.js 22+ is required" -ForegroundColor $ErrorColor
            exit 1
        }
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
Write-Host "[*] npm registry: $NpmRegistry" -ForegroundColor $MutedColor

if ($DryRun) {
    Write-Host "  [dry-run] npm install -g $spec" -ForegroundColor $MutedColor
} else {
    # Build the full command as a string to avoid argument parsing issues
    # Note: removed --loglevel error so users can see install progress
    $npmCmd = "npm install -g `"$spec`" --no-fund --no-audit --registry `"$NpmRegistry`""
    
    # Use cmd /c to execute npm reliably
    cmd /c $npmCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: npm install failed (exit code: $LASTEXITCODE)" -ForegroundColor $ErrorColor
        Write-Host "Try running manually: npm install -g $spec --registry $NpmRegistry" -ForegroundColor $InfoColor
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    Write-Host "[OK] OpenClaw installed successfully" -ForegroundColor $SuccessColor
    
    # For non-admin users, ensure npm bin is in PATH permanently
    if (-not $script:IsAdmin) {
        Ensure-NpmInPath
    }
    
    # Refresh PATH so openclaw-cn is available
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
    Write-Host "[!] Could not verify installation - you may need to restart your terminal" -ForegroundColor $WarnColor
}

# Run onboarding
if (-not $NoOnboard -and -not $DryRun) {
    # Check if openclaw-cn is available
    $openclawAvailable = $false
    try {
        $testCmd = & openclaw-cn --version 2>&1
        if ($testCmd -and $testCmd -notmatch 'not recognized') {
            $openclawAvailable = $true
        }
    } catch {
        # Ignore
    }
    
    if ($openclawAvailable) {
        Write-Host ""
        Write-Host "[*] Starting onboarding..." -ForegroundColor $InfoColor
        Write-Host ""
        & openclaw-cn onboard
    } else {
        Write-Host ""
        Write-Host "[!] openclaw-cn not found in PATH" -ForegroundColor $WarnColor
        Write-Host "Please restart your terminal and run: openclaw-cn onboard" -ForegroundColor $InfoColor
    }
} else {
    Write-Host ""
    Write-Host "Tip: Run 'openclaw-cn onboard' to start setup" -ForegroundColor $InfoColor
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor $SuccessColor
Write-Host ""

# Keep window open if running interactively
if ($Host.UI.RawUI.WindowTitle) {
    Write-Host "Press any key to exit..." -ForegroundColor $MutedColor
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}