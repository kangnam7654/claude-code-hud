# Fetch Claude Max plan usage from Anthropic OAuth API (Windows PowerShell)
# Writes to cache file; intended to run in background from statusline

$ErrorActionPreference = "Stop"

$claudeDir = Join-Path $env:USERPROFILE ".claude"
$cacheFile = Join-Path $claudeDir "plan-usage-cache.json"
$credFile = Join-Path $claudeDir ".credentials.json"

# Read OAuth access token
$credJson = $null
if (Test-Path $credFile) {
    $credJson = Get-Content $credFile -Raw | ConvertFrom-Json
}

if (-not $credJson) {
    '{"error":"no credentials"}' | Out-File $cacheFile -Encoding utf8
    exit 1
}

$accessToken = if ($credJson.claudeAiOauth.accessToken) { $credJson.claudeAiOauth.accessToken }
               elseif ($credJson.accessToken) { $credJson.accessToken }
               else { $null }

if (-not $accessToken) {
    '{"error":"no token"}' | Out-File $cacheFile -Encoding utf8
    exit 1
}

# Call Anthropic OAuth usage API
try {
    $headers = @{
        "Authorization"  = "Bearer $accessToken"
        "anthropic-beta" = "oauth-2025-04-20"
        "Content-Type"   = "application/json"
    }
    $response = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" `
        -Headers $headers -TimeoutSec 10
} catch {
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $errMsg = $_.Exception.Message -replace '"', '\"'
    "{`"error`":`"api failed: $errMsg`",`"timestamp`":$ts}" | Out-File $cacheFile -Encoding utf8
    exit 1
}

# Parse and write cache
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$parsed = @{
    timestamp            = $ts
    five_hour_pct        = [Math]::Floor([double]($response.five_hour.utilization ?? 0))
    five_hour_resets_at  = $response.five_hour.resets_at
    seven_day_pct        = [Math]::Floor([double]($response.seven_day.utilization ?? 0))
    seven_day_resets_at  = $response.seven_day.resets_at
    sonnet_weekly_pct    = [Math]::Floor([double]($response.seven_day_sonnet.utilization ?? 0))
    sonnet_weekly_resets_at = $response.seven_day_sonnet.resets_at
    opus_weekly_pct      = [Math]::Floor([double]($response.seven_day_opus.utilization ?? 0))
    opus_weekly_resets_at = $response.seven_day_opus.resets_at
}

$parsedJson = $parsed | ConvertTo-Json -Compress
$tmpFile = "$cacheFile.tmp"
$parsedJson | Out-File $tmpFile -Encoding utf8
Move-Item -Path $tmpFile -Destination $cacheFile -Force

exit 0
