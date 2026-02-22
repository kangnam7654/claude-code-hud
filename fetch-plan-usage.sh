#!/bin/bash
# Fetch Claude Max plan usage from Anthropic OAuth API
# Writes to cache file; intended to run in background from statusline
#
# API: api.anthropic.com/api/oauth/usage
# Auth: OAuth token from ~/.claude/.credentials.json

CACHE_FILE="/tmp/claude-plan-usage.json"
CRED_FILE="$HOME/.claude/.credentials.json"

# Read OAuth access token
# Try credentials file first (Linux), then macOS Keychain
CRED_JSON=""
if [ -f "$CRED_FILE" ]; then
    CRED_JSON=$(cat "$CRED_FILE")
elif command -v security &>/dev/null; then
    CRED_JSON=$(security find-generic-password -s "Claude Code-credentials" -a "$USER" -w 2>/dev/null)
fi

if [ -z "$CRED_JSON" ]; then
    echo '{"error":"no credentials"}' > "$CACHE_FILE"
    exit 1
fi

ACCESS_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // .accessToken // empty')
if [ -z "$ACCESS_TOKEN" ]; then
    echo '{"error":"no token"}' > "$CACHE_FILE"
    exit 1
fi

# Call Anthropic OAuth usage API
RESPONSE=$(curl -s --max-time 10 \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

if [ -z "$RESPONSE" ]; then
    echo "{\"error\":\"api failed\",\"timestamp\":$(date +%s)}" > "$CACHE_FILE"
    exit 1
fi

# Parse and write cache with timestamp
PARSED=$(echo "$RESPONSE" | jq -c \
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
if [ -n "$PARSED" ] && echo "$PARSED" | jq -e '.timestamp' >/dev/null 2>&1; then
    echo "$PARSED" > "$CACHE_FILE"
else
    echo "{\"error\":\"parse failed\",\"timestamp\":$(date +%s),\"raw\":$(echo "$RESPONSE" | head -c 500 | jq -Rs .)}" > "$CACHE_FILE"
    exit 1
fi

exit 0
