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
# Use -D to capture headers (for retry-after on 429)
HEADER_FILE=$(mktemp)
set +e
RESPONSE=$(curl -sS --max-time 10 -w '\n%{http_code}' \
    -D "$HEADER_FILE" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>&1)
curl_exit=$?
set -e

HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -1)
RESPONSE=$(printf '%s' "$RESPONSE" | sed '$d')

if [ $curl_exit -ne 0 ] || [ "${HTTP_CODE:-0}" -ge 400 ] 2>/dev/null; then
    # On 429: record retry-after so statusline skips refresh until then
    if [ "$HTTP_CODE" = "429" ]; then
        RETRY_AFTER=$(grep -i '^retry-after:' "$HEADER_FILE" | tr -d '\r' | awk '{print $2}')
        RETRY_AFTER=${RETRY_AFTER:-60}
        BACKOFF_UNTIL=$(( $(date +%s) + RETRY_AFTER ))
        # Preserve existing usage data, just add backoff marker
        if [ -f "$CACHE_FILE" ] && ! jq -e '.error' "$CACHE_FILE" >/dev/null 2>&1; then
            jq -c --arg bu "$BACKOFF_UNTIL" '. + {backoff_until: ($bu | tonumber)}' "$CACHE_FILE" \
                > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        else
            echo "{\"error\":\"rate limited\",\"timestamp\":$(date +%s),\"backoff_until\":$BACKOFF_UNTIL}" > "$CACHE_FILE"
        fi
    else
        # Other errors: keep old cache data but bump timestamp to avoid retrying every call
        if [ -f "$CACHE_FILE" ] && jq -e '.five_hour_pct' "$CACHE_FILE" >/dev/null 2>&1; then
            jq --arg ts "$(date +%s)" '.timestamp = ($ts | tonumber)' "$CACHE_FILE" > "${CACHE_FILE}.tmp" \
                && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        fi
    fi
    rm -f "$HEADER_FILE"
    exit 1
fi
rm -f "$HEADER_FILE"

# Parse and write cache with timestamp
PARSED=$(printf '%s\n' "$RESPONSE" | jq -c \
    --arg ts "$(date +%s)" \
    '{
        timestamp: ($ts | tonumber),
        five_hour_pct: ((.five_hour.utilization // 0) | round),
        five_hour_resets_at: (.five_hour.resets_at // null),
        seven_day_pct: ((.seven_day.utilization // 0) | round),
        seven_day_resets_at: (.seven_day.resets_at // null),
        sonnet_weekly_pct: ((.seven_day_sonnet.utilization // 0) | round),
        sonnet_weekly_resets_at: (.seven_day_sonnet.resets_at // null),
        opus_weekly_pct: ((.seven_day_opus.utilization // 0) | round),
        opus_weekly_resets_at: (.seven_day_opus.resets_at // null)
    }' 2>/dev/null)

# Only write cache if jq succeeded and produced valid JSON
if [ -n "$PARSED" ] && printf '%s\n' "$PARSED" | jq -e '.timestamp' >/dev/null 2>&1; then
    printf '%s\n' "$PARSED" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
else
    # Parse failed — keep old cache data but bump timestamp
    if [ -f "$CACHE_FILE" ] && jq -e '.five_hour_pct' "$CACHE_FILE" >/dev/null 2>&1; then
        jq --arg ts "$(date +%s)" '.timestamp = ($ts | tonumber)' "$CACHE_FILE" > "${CACHE_FILE}.tmp" \
            && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    fi
    exit 1
fi

exit 0
