# Claude Code HUD - Usage Dashboard (Windows PowerShell)
# Line 1: Model | Session Cost | Time
# Line 2: Context bar | Tokens
# Line 3: Plan usage (5h session + 7d weekly) with reset timers

$ErrorActionPreference = "SilentlyContinue"

# --- Helper functions ---

function Get-ColorByPct($pct) {
    $p = [int]($pct -replace '[^0-9]', '0')
    if ($p -ge 80) { return "`e[31m" }      # RED
    elseif ($p -ge 50) { return "`e[33m" }   # YELLOW
    else { return "`e[32m" }                  # GREEN
}

function New-Bar($pct, $width = 20) {
    $p = [Math]::Min([Math]::Max([int]($pct -replace '[^0-9]', '0'), 0), 100)
    $filled = [Math]::Min([int]($p * $width / 100), $width)
    $empty = $width - $filled
    return ([string]::new([char]0x2588, $filled) + [string]::new([char]0x2591, $empty))
}

function Format-Tokens($n) {
    $v = [long]($n -replace '[^0-9]', '0')
    if ($v -ge 1000000) { return "{0:F1}M" -f ($v / 1000000) }
    elseif ($v -ge 1000) { return "{0:F1}K" -f ($v / 1000) }
    else { return "$v" }
}

function Format-Time($ms) {
    $v = [long]($ms -replace '[^0-9]', '0')
    $totalSec = [Math]::Floor($v / 1000)
    $hrs = [Math]::Floor($totalSec / 3600)
    $mins = [Math]::Floor(($totalSec % 3600) / 60)
    $secs = $totalSec % 60
    if ($hrs -gt 0) { return "{0}h {1}m" -f $hrs, $mins }
    elseif ($mins -gt 0) { return "{0}m {1}s" -f $mins, $secs }
    else { return "{0}s" -f $secs }
}

function Format-Cost($cost) {
    $v = [double]($cost -replace '[^0-9.]', '0')
    if ($v -ge 1) { return "`${0:F2}" -f $v }
    else { return "`${0:F4}" -f $v }
}

function ConvertTo-Epoch($isoString) {
    try {
        $dt = [DateTimeOffset]::Parse($isoString)
        return [long]($dt.ToUnixTimeSeconds())
    } catch { return $null }
}

function Format-Remaining($resetAt) {
    if (-not $resetAt -or $resetAt -eq "null") { return "?" }
    $resetEpoch = ConvertTo-Epoch $resetAt
    if (-not $resetEpoch) { return "?" }
    $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = $resetEpoch - $nowEpoch
    if ($diff -le 0) { return "soon" }
    $days = [Math]::Floor($diff / 86400)
    $hrs = [Math]::Floor(($diff % 86400) / 3600)
    $mins = [Math]::Floor(($diff % 3600) / 60)
    if ($days -gt 0) { return "{0}d {1}h" -f $days, $hrs }
    elseif ($hrs -gt 0) { return "{0}h {1}m" -f $hrs, $mins }
    else { return "{0}m" -f $mins }
}

# --- Main ---

$input = $Input | Out-String
if (-not $input.Trim()) {
    Write-Host "HUD: no data"
    exit 0
}

try { $data = $input | ConvertFrom-Json } catch {
    Write-Host "HUD: no data"
    exit 0
}

# Parse JSON data
$model     = if ($data.model.display_name) { $data.model.display_name } else { "unknown" }
$cost      = if ($data.cost.total_cost_usd) { [double]$data.cost.total_cost_usd } else { 0 }
$durationMs = if ($data.cost.total_duration_ms) { $data.cost.total_duration_ms } else { 0 }
$apiDurMs  = if ($data.cost.total_api_duration_ms) { $data.cost.total_api_duration_ms } else { 0 }
$pct       = if ($data.context_window.used_percentage) { [int]$data.context_window.used_percentage } else { 0 }
$inTokens  = if ($data.context_window.total_input_tokens) { $data.context_window.total_input_tokens } else { 0 }
$outTokens = if ($data.context_window.total_output_tokens) { $data.context_window.total_output_tokens } else { 0 }

# Paths
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$planCache = Join-Path $claudeDir "plan-usage-cache.json"
$fetchScript = Join-Path $claudeDir "fetch-plan-usage.ps1"
$logFile = Join-Path $claudeDir "usage-log.jsonl"

# Colors
$BOLD    = "`e[1m"
$DIM     = "`e[2m"
$CYAN    = "`e[36m"
$GREEN   = "`e[32m"
$YELLOW  = "`e[33m"
$RED     = "`e[31m"
$MAGENTA = "`e[35m"
$WHITE   = "`e[97m"
$BLUE    = "`e[34m"
$RESET   = "`e[0m"

# Format session data
$ctxColor = Get-ColorByPct $pct
$costFmt  = Format-Cost $cost
$inFmt    = Format-Tokens $inTokens
$outFmt   = Format-Tokens $outTokens
$wallTime = Format-Time $durationMs
$apiTime  = Format-Time $apiDurMs

# --- Plan usage (background refresh) ---
$plan5h = "?"
$plan5hReset = ""
$plan7d = "?"
$plan7dReset = ""

if (Test-Path $fetchScript) {
    $needRefresh = $false
    if (-not (Test-Path $planCache)) {
        $needRefresh = $true
    } else {
        try {
            $cacheData = Get-Content $planCache -Raw | ConvertFrom-Json
            $cacheAge = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$cacheData.timestamp
            if ($cacheAge -gt 30) { $needRefresh = $true }
        } catch { $needRefresh = $true }
    }
    if ($needRefresh) {
        Start-Process -NoNewWindow -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", $fetchScript *> $null
    }
}

# Read cached plan usage
if (Test-Path $planCache) {
    try {
        $cache = Get-Content $planCache -Raw | ConvertFrom-Json
        if (-not $cache.error) {
            $plan5h = if ($cache.five_hour_pct) { $cache.five_hour_pct } else { 0 }
            $plan5hResetAt = $cache.five_hour_resets_at
            $plan7d = if ($cache.seven_day_pct) { $cache.seven_day_pct } else { 0 }
            $plan7dResetAt = $cache.seven_day_resets_at
            $plan5hReset = Format-Remaining $plan5hResetAt
            $plan7dReset = Format-Remaining $plan7dResetAt
        }
    } catch {}
}

$plan5hColor = Get-ColorByPct $plan5h
$plan7dColor = Get-ColorByPct $plan7d

# --- Cumulative daily/monthly cost (past sessions only) ---
$today = Get-Date -Format "yyyy-MM-dd"
$month = Get-Date -Format "yyyy-MM"
$dailyTotal = 0.0
$monthlyTotal = 0.0

if (Test-Path $logFile) {
    try {
        $lines = Get-Content $logFile
        foreach ($line in $lines) {
            $entry = $line | ConvertFrom-Json
            if ($entry.date -eq $today) { $dailyTotal += [double]$entry.cost_usd }
            if ($entry.date -and $entry.date.StartsWith($month)) { $monthlyTotal += [double]$entry.cost_usd }
        }
    } catch {}
}

$dailyFmt = Format-Cost $dailyTotal
$monthlyFmt = Format-Cost $monthlyTotal

# --- Output ---
$ctxBar   = New-Bar $pct 20
$plan5hBar = New-Bar $plan5h 20
$plan7dBar = New-Bar $plan7d 20

Write-Host "${BOLD}${CYAN}${model}${RESET} ${DIM}|${RESET} ${WHITE}${wallTime}${RESET} ${DIM}(api:${apiTime})${RESET} ${DIM}|${RESET} ${YELLOW}${costFmt}${RESET} ${DIM}|${RESET} ${BLUE}d:${dailyFmt} m:${monthlyFmt}${RESET} ${DIM}|${RESET} ${MAGENTA}in:${inFmt} out:${outFmt}${RESET}"
Write-Host "ctx  ${ctxColor}[${ctxBar}]${RESET} ${BOLD}${pct}%${RESET}"
Write-Host "5h   ${plan5hColor}[${plan5hBar}]${RESET} ${BOLD}${plan5h}%${RESET}  ${DIM}reset ${plan5hReset}${RESET}"
Write-Host "week ${plan7dColor}[${plan7dBar}]${RESET} ${BOLD}${plan7d}%${RESET}  ${DIM}reset ${plan7dReset}${RESET}"

# Save session snapshot for SessionEnd hook
$input | Out-File -FilePath (Join-Path $claudeDir ".current-session.json") -Encoding utf8 -Force 2>$null
