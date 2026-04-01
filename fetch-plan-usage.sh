#!/bin/bash
# Fetch Claude Max plan usage from Anthropic OAuth API
# Writes to cache file; intended to run in background from statusline
#
# API: api.anthropic.com/api/oauth/usage
# Auth: OAuth token from ~/.claude/.credentials.json

set -euo pipefail

CACHE_FILE="$HOME/.claude/plan-usage-cache.json"
CRED_FILE="$HOME/.claude/.credentials.json"

# Read OAuth access token
# Try credentials file first, then macOS Keychain
# On macOS, claudeAiOauth may be in Keychain while file only has mcpOAuth
ACCESS_TOKEN=""

if [ -f "$CRED_FILE" ]; then
    ACCESS_TOKEN=$(jq -r '.claudeAiOauth.accessToken // .accessToken // empty' "$CRED_FILE" 2>/dev/null)
fi

if [ -z "$ACCESS_TOKEN" ] && command -v security &>/dev/null; then
    KEYCHAIN_JSON=$(security find-generic-password -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null) || true
    if [ -n "$KEYCHAIN_JSON" ]; then
        ACCESS_TOKEN=$(printf '%s\n' "$KEYCHAIN_JSON" | jq -r '.claudeAiOauth.accessToken // .accessToken // empty')
    fi
fi
if [ -z "$ACCESS_TOKEN" ]; then
    echo '{"error":"no token"}' > "$CACHE_FILE"
    exit 1
fi

# Call Anthropic OAuth usage API
# Use if-guard so set -e doesn't kill the script before error handling
if ! RESPONSE=$(curl -sS --fail --max-time 10 \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>&1); then
    printf '%s' "$RESPONSE" | head -c 200 | jq -Rsc --arg ts "$(date +%s)" \
        '{error: ("curl failed: " + .), timestamp: ($ts | tonumber)}' > "$CACHE_FILE"
    exit 1
fi

# Parse and write cache with timestamp
PARSED=$(printf '%s\n' "$RESPONSE" | jq -c \
    --arg ts "$(date +%s)" \
    '{
        timestamp: ($ts | tonumber),
        five_hour_pct: ((.five_hour.utilization // 0) | floor),
        five_hour_resets_at: (.five_hour.resets_at // null),
        seven_day_pct: ((.seven_day.utilization // 0) | floor),
        seven_day_resets_at: (.seven_day.resets_at // null),
        sonnet_weekly_pct: ((.seven_day_sonnet.utilization // 0) | floor),
        sonnet_weekly_resets_at: (.seven_day_sonnet.resets_at // null),
        opus_weekly_pct: ((.seven_day_opus.utilization // 0) | floor),
        opus_weekly_resets_at: (.seven_day_opus.resets_at // null)
    }' 2>/dev/null)

# Only write cache if jq succeeded and produced valid JSON
if [ -n "$PARSED" ] && printf '%s\n' "$PARSED" | jq -e '.timestamp' >/dev/null 2>&1; then
    printf '%s\n' "$PARSED" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
else
    printf '%s' "$RESPONSE" | head -c 500 | jq -Rsc --arg ts "$(date +%s)" \
        '{error: "parse failed", timestamp: ($ts | tonumber), raw: .}' > "$CACHE_FILE"
    exit 1
fi

exit 0
