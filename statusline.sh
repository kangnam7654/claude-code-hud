#!/bin/bash
# Claude Code HUD - Usage Dashboard
# Line 1: Model | Session Cost | Time
# Line 2: Context bar | Tokens
# Line 3: Plan usage (5h session + 7d weekly) with reset timers

input=$(cat)

# Parse JSON data
MODEL=$(echo "$input" | jq -r '.model.display_name // "unknown"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
API_DURATION_MS=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUTPUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Paths
PLAN_CACHE="/tmp/claude-plan-usage.json"
FETCH_SCRIPT="$HOME/.claude/fetch-plan-usage.sh"
LOG_FILE="$HOME/.claude/usage-log.jsonl"

# Colors
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
WHITE='\033[97m'
BLUE='\033[34m'
RESET='\033[0m'

# --- Helper functions ---

color_by_pct() {
    local pct=$1
    if [ "${pct:-0}" -ge 80 ] 2>/dev/null; then echo "$RED"
    elif [ "${pct:-0}" -ge 50 ] 2>/dev/null; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

make_bar() {
    local pct=$1 width=$2
    local filled=$((pct * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$((width - filled))
    printf "%${filled}s" | sed 's/ /█/g'
    printf "%${empty}s" | sed 's/ /░/g'
}

format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
    else
        printf "%d" "$n"
    fi
}

format_time() {
    local ms=$1
    local total_sec=$((ms / 1000))
    local hrs=$((total_sec / 3600))
    local mins=$(((total_sec % 3600) / 60))
    local secs=$((total_sec % 60))
    if [ "$hrs" -gt 0 ]; then printf "%dh %dm" "$hrs" "$mins"
    elif [ "$mins" -gt 0 ]; then printf "%dm %ds" "$mins" "$secs"
    else printf "%ds" "$secs"; fi
}

format_cost() {
    local cost=$1
    local int_part=$(echo "$cost" | cut -d. -f1)
    if [ "${int_part:-0}" -ge 1 ] 2>/dev/null; then printf '$%.2f' "$cost"
    else printf '$%.4f' "$cost"; fi
}

# Format ISO timestamp to "Xh Ym" or "Xd Yh" remaining
format_remaining() {
    local reset_at=$1
    if [ -z "$reset_at" ] || [ "$reset_at" = "null" ]; then
        echo "?"
        return
    fi
    local reset_epoch=$(date -d "$reset_at" +%s 2>/dev/null)
    local now_epoch=$(date +%s)
    if [ -z "$reset_epoch" ]; then echo "?"; return; fi
    local diff=$((reset_epoch - now_epoch))
    if [ "$diff" -le 0 ]; then echo "soon"; return; fi
    local days=$((diff / 86400))
    local hrs=$(((diff % 86400) / 3600))
    local mins=$(((diff % 3600) / 60))
    if [ "$days" -gt 0 ]; then printf "%dd %dh" "$days" "$hrs"
    elif [ "$hrs" -gt 0 ]; then printf "%dh %dm" "$hrs" "$mins"
    else printf "%dm" "$mins"; fi
}

# --- Context bar ---
CTX_COLOR=$(color_by_pct "$PCT")
CTX_BAR=$(make_bar "$PCT" 15)

COST_FMT=$(format_cost "$COST")
IN_FMT=$(format_tokens "$INPUT_TOKENS")
OUT_FMT=$(format_tokens "$OUTPUT_TOKENS")
WALL_TIME=$(format_time "$DURATION_MS")
API_TIME=$(format_time "$API_DURATION_MS")

# --- Plan usage (background refresh) ---
PLAN_5H="?"
PLAN_5H_RESET=""
PLAN_7D="?"
PLAN_7D_RESET=""

# Refresh cache in background if stale (>30s) or missing
if [ -f "$FETCH_SCRIPT" ]; then
    NEED_REFRESH=false
    if [ ! -f "$PLAN_CACHE" ]; then
        NEED_REFRESH=true
    else
        CACHE_AGE=$(( $(date +%s) - $(jq -r '.timestamp // 0' "$PLAN_CACHE" 2>/dev/null || echo 0) ))
        [ "$CACHE_AGE" -gt 30 ] && NEED_REFRESH=true
    fi
    if $NEED_REFRESH; then
        "$FETCH_SCRIPT" &>/dev/null &
    fi
fi

# Read cached plan usage
if [ -f "$PLAN_CACHE" ] && [ -z "$(jq -r '.error // empty' "$PLAN_CACHE" 2>/dev/null)" ]; then
    PLAN_5H=$(jq -r '.five_hour_pct // 0' "$PLAN_CACHE")
    PLAN_5H_RESET_AT=$(jq -r '.five_hour_resets_at // empty' "$PLAN_CACHE")
    PLAN_7D=$(jq -r '.seven_day_pct // 0' "$PLAN_CACHE")
    PLAN_7D_RESET_AT=$(jq -r '.seven_day_resets_at // empty' "$PLAN_CACHE")

    PLAN_5H_RESET=$(format_remaining "$PLAN_5H_RESET_AT")
    PLAN_7D_RESET=$(format_remaining "$PLAN_7D_RESET_AT")
fi

PLAN_5H_COLOR=$(color_by_pct "$PLAN_5H")
PLAN_7D_COLOR=$(color_by_pct "$PLAN_7D")

# --- Cumulative daily/monthly cost ---
TODAY=$(date +%Y-%m-%d)
MONTH=$(date +%Y-%m)
DAILY_TOTAL="0"
MONTHLY_TOTAL="0"

if [ -f "$LOG_FILE" ]; then
    DAILY_TOTAL=$(jq -rs "[.[] | select(.date == \"$TODAY\") | .cost_usd] | add // 0" "$LOG_FILE")
    MONTHLY_TOTAL=$(jq -rs "[.[] | select(.date | startswith(\"$MONTH\")) | .cost_usd] | add // 0" "$LOG_FILE")
fi

# Add current session
DAILY_WITH=$(echo "$DAILY_TOTAL + $COST" | bc)
MONTHLY_WITH=$(echo "$MONTHLY_TOTAL + $COST" | bc)
DAILY_FMT=$(format_cost "$DAILY_WITH")
MONTHLY_FMT=$(format_cost "$MONTHLY_WITH")

# --- Output ---

# Line 1: Model | Time | Session$ | Daily$ Monthly$ | Tokens
echo -e "${BOLD}${CYAN}${MODEL}${RESET} ${DIM}|${RESET} ${WHITE}${WALL_TIME}${RESET} ${DIM}(api:${API_TIME})${RESET} ${DIM}|${RESET} ${YELLOW}${COST_FMT}${RESET} ${DIM}|${RESET} ${BLUE}d:${DAILY_FMT} m:${MONTHLY_FMT}${RESET} ${DIM}|${RESET} ${MAGENTA}in:${IN_FMT} out:${OUT_FMT}${RESET}"

# Line 2: ctx bar with label
CTX_BAR=$(make_bar "$PCT" 20)
echo -e "ctx  ${CTX_COLOR}[${CTX_BAR}]${RESET} ${BOLD}${PCT}%${RESET}"

# Line 3: 5h session bar
PLAN_5H_BAR=$(make_bar "$PLAN_5H" 20)
echo -e "5h   ${PLAN_5H_COLOR}[${PLAN_5H_BAR}]${RESET} ${BOLD}${PLAN_5H}%${RESET}  ${DIM}reset ${PLAN_5H_RESET}${RESET}"

# Line 4: 7d weekly bar
PLAN_7D_BAR=$(make_bar "$PLAN_7D" 20)
echo -e "week ${PLAN_7D_COLOR}[${PLAN_7D_BAR}]${RESET} ${BOLD}${PLAN_7D}%${RESET}  ${DIM}reset ${PLAN_7D_RESET}${RESET}"
