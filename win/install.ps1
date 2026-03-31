# Claude Code HUD - Install / Uninstall Script (Windows PowerShell)
# Usage: .\install.ps1          (install)
#        .\install.ps1 -Uninstall  (uninstall)

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# --- Constants ---
$scriptDir = $PSScriptRoot
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsFile = Join-Path $claudeDir "settings.json"

$scripts = @(
    "statusline.ps1"
    "fetch-plan-usage.ps1"
    "log-session.ps1"
)

# --- Helpers ---
function Write-OK($msg)   { Write-Host "  $([char]0x2713) $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "  X $msg" -ForegroundColor Red }

# --- Uninstall ---
if ($Uninstall) {
    Write-Host "`nClaude Code HUD - Uninstall`n" -ForegroundColor Cyan

    foreach ($file in $scripts) {
        $dest = Join-Path $claudeDir $file
        if (Test-Path $dest) {
            Remove-Item $dest -Force
            Write-OK "Removed: $dest"
        } else {
            Write-Host "  $dest not found - skipping"
        }
    }

    # Remove settings entries
    if (Test-Path $settingsFile) {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
        if ($settings.statusLine) { $settings.PSObject.Properties.Remove("statusLine") }
        if ($settings.hooks.SessionEnd) {
            $settings.hooks.PSObject.Properties.Remove("SessionEnd")
            if (-not $settings.hooks.PSObject.Properties.Count) {
                $settings.PSObject.Properties.Remove("hooks")
            }
        }
        $settings | ConvertTo-Json -Depth 10 | Out-File $settingsFile -Encoding utf8
        Write-OK "Removed HUD entries from settings.json"
    }

    # Ask about log/cache
    $logFile = Join-Path $claudeDir "usage-log.jsonl"
    $cacheFile = Join-Path $claudeDir "plan-usage-cache.json"

    if (Test-Path $logFile) {
        $ans = Read-Host "  Delete usage log ($logFile)? [y/N]"
        if ($ans -match "^[Yy]$") {
            Remove-Item $logFile -Force
            Write-OK "Deleted $logFile"
        } else {
            Write-Host "  Kept $logFile"
        }
    }

    if (Test-Path $cacheFile) {
        Remove-Item $cacheFile -Force
        Write-OK "Deleted cache: $cacheFile"
    }

    Write-Host ""
    Write-OK "Uninstall complete. Restart Claude Code to apply changes."
    exit 0
}

# =============================================================
# Install
# =============================================================
Write-Host "`nClaude Code HUD - Install`n" -ForegroundColor Cyan

# 1. Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Err "PowerShell 7+ required (current: $($PSVersionTable.PSVersion))"
    Write-Host "  Install: winget install Microsoft.PowerShell"
    exit 1
}
Write-OK "PowerShell $($PSVersionTable.PSVersion) OK"

# 2. ~/.claude directory
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

# 3. Copy scripts
Write-Host "`nCopying scripts..." -ForegroundColor White
foreach ($file in $scripts) {
    $src = Join-Path $scriptDir $file
    $dest = Join-Path $claudeDir $file

    if (-not (Test-Path $src)) {
        Write-Err "Source not found: $src"
        exit 1
    }

    Copy-Item $src $dest -Force
    Write-OK "$file -> $dest"
}

# 4. settings.json update
Write-Host "`nUpdating settings.json..." -ForegroundColor White

$hudConfig = @{
    statusLine = @{
        type    = "command"
        command = "pwsh -NoProfile -File `"$claudeDir\statusline.ps1`""
    }
    hooks = @{
        SessionEnd = @(
            @{
                hooks = @(
                    @{
                        type    = "command"
                        command = "pwsh -NoProfile -File `"$claudeDir\log-session.ps1`""
                    }
                )
            }
        )
    }
}

if (-not (Test-Path $settingsFile)) {
    $hudConfig | ConvertTo-Json -Depth 10 | Out-File $settingsFile -Encoding utf8
    Write-OK "Created $settingsFile"
} else {
    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
    $updated = $false

    if (-not $settings.statusLine) {
        $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $hudConfig.statusLine
        Write-OK "Added statusLine config"
        $updated = $true
    } else {
        Write-Warn "statusLine already exists - skipping"
    }

    $hasHook = $false
    try { $hasHook = $null -ne $settings.hooks.SessionEnd } catch {}
    if (-not $hasHook) {
        if (-not $settings.hooks) {
            $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{}
        }
        $settings.hooks | Add-Member -NotePropertyName "SessionEnd" -NotePropertyValue $hudConfig.hooks.SessionEnd
        Write-OK "Added SessionEnd hook"
        $updated = $true
    } else {
        Write-Warn "hooks.SessionEnd already exists - skipping"
    }

    if ($updated) {
        $settings | ConvertTo-Json -Depth 10 | Out-File $settingsFile -Encoding utf8
    } else {
        Write-Host "  No changes needed - settings already configured"
    }
}

# 5. Success
Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Restart Claude Code to activate the HUD."
Write-Host "To uninstall: .\install.ps1 -Uninstall" -ForegroundColor DarkGray
