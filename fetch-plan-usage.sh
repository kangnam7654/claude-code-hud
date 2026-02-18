#!/bin/bash
# Fetch Claude Max plan usage from Anthropic OAuth API
# Writes to cache file; intended to run in background from statusline
#
# API: api.anthropic.com/api/oauth/usage
# Auth: OAuth token from ~/.claude/.credentials.json

CACHE_FILE="/tmp/claude-plan-usage.json"
CRED_FILE="$HOME/.claude/.credentials.json"

# Read OAuth access token
if [ ! -f "$CRED_FILE" ]; then
    echo '{"error":"no credentials"}' > "$CACHE_FILE"
    exit 1
fi

ACCESS_TOKEN=$(jq -r '.claudeAiOauth.accessToken // .accessToken // empty' "$CRED_FILE")
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
echo "$RESPONSE" | jq -c \
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
    }' > "$CACHE_FILE" 2>/dev/null

exit 0
