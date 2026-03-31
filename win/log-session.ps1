# Claude Code SessionEnd Hook - Logs session metrics to usage-log.jsonl (Windows PowerShell)
# Reads session data from snapshot file written by statusline.ps1

$ErrorActionPreference = "Stop"

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$logFile = Join-Path $claudeDir "usage-log.jsonl"
$snapshot = Join-Path $claudeDir ".current-session.json"

# Ensure directory exists
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

# Read session data from statusline snapshot
if (-not (Test-Path $snapshot)) { exit 0 }

$input = Get-Content $snapshot -Raw
if (-not $input.Trim()) { exit 0 }

try {
    $data = $input | ConvertFrom-Json

    $entry = @{
        timestamp    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        date         = (Get-Date).ToString("yyyy-MM-dd")
        session_id   = $data.session_id
        model        = $data.model.id
        cost_usd     = if ($data.cost.total_cost_usd) { [double]$data.cost.total_cost_usd } else { 0 }
        duration_ms  = if ($data.cost.total_duration_ms) { $data.cost.total_duration_ms } else { 0 }
        api_duration_ms = if ($data.cost.total_api_duration_ms) { $data.cost.total_api_duration_ms } else { 0 }
        input_tokens = if ($data.context_window.total_input_tokens) { $data.context_window.total_input_tokens } else { 0 }
        output_tokens = if ($data.context_window.total_output_tokens) { $data.context_window.total_output_tokens } else { 0 }
    }

    $line = $entry | ConvertTo-Json -Compress
    Add-Content -Path $logFile -Value $line -Encoding utf8
} catch {
    # Silent failure - don't break session end
}

# Clean up snapshot
Remove-Item -Path $snapshot -Force -ErrorAction SilentlyContinue
