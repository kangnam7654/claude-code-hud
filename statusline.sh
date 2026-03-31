#!/bin/bash
# Claude Code HUD - Usage Dashboard
# Line 1: Model | Session Cost | Time
# Line 2: Context bar | Tokens
# Line 3: Plan usage (5h session + 7d weekly) with reset timers

# Source utility functions (follow symlink to find lib/)
_hud_script="${BASH_SOURCE[0]}"
[ -L "$_hud_script" ] && _hud_script="$(readlink "$_hud_script")"
_hud_dir="$(cd "$(dirname "$_hud_script")" && pwd -P)"
source "${_hud_dir}/lib/hud-utils.sh"

# Main-guard: only execute when run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

input=$(cat)

# Validate stdin: empty or invalid JSON -> fallback
if [ -z "$input" ] || ! printf '%s\n' "$input" | jq -e . >/dev/null 2>&1; then
    echo "HUD: no data"
    exit 0
fi

# Parse JSON data
MODEL=$(printf '%s\n' "$input" | jq -r '.model.display_name // "unknown"')
COST=$(printf '%s\n' "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(printf '%s\n' "$input" | jq -r '.cost.total_duration_ms // 0')
API_DURATION_MS=$(printf '%s\n' "$input" | jq -r '.cost.total_api_duration_ms // 0')
PCT=$(printf '%s\n' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
INPUT_TOKENS=$(printf '%s\n' "$input" | jq -r '.context_window.total_input_tokens // 0')
OUTPUT_TOKENS=$(printf '%s\n' "$input" | jq -r '.context_window.total_output_tokens // 0')

# Validate numeric fields
[[ "$COST" =~ ^[0-9]*\.?[0-9]+$ ]] || COST=0
[[ "$PCT" =~ ^[0-9]+$ ]] || PCT=0

# Paths
PLAN_CACHE="$HOME/.claude/plan-usage-cache.json"
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

# --- Context bar ---
CTX_COLOR=$(color_by_pct "$PCT")

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
        cache_ts=$(jq -r '.timestamp // 0' "$PLAN_CACHE" 2>/dev/null || echo 0)
        [[ "$cache_ts" =~ ^[0-9]+$ ]] || cache_ts=0
        CACHE_AGE=$(( $(date +%s) - cache_ts ))
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
    DAILY_TOTAL=$(jq -rs --arg today "$TODAY" '[.[] | select(.date == $today) | .cost_usd] | add // 0' "$LOG_FILE")
    MONTHLY_TOTAL=$(jq -rs --arg month "$MONTH" '[.[] | select(.date | startswith($month)) | .cost_usd] | add // 0' "$LOG_FILE")
fi

[[ "$DAILY_TOTAL" =~ ^[0-9]*\.?[0-9]+$ ]] || DAILY_TOTAL=0
[[ "$MONTHLY_TOTAL" =~ ^[0-9]*\.?[0-9]+$ ]] || MONTHLY_TOTAL=0

# Past sessions only (not including current)
DAILY_FMT=$(format_cost "$DAILY_TOTAL")
MONTHLY_FMT=$(format_cost "$MONTHLY_TOTAL")

# --- Output ---

# Line 1: Model | Time | Session$ | Daily$ Monthly$ (past sessions) | Tokens
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

# Save current session snapshot for SessionEnd hook to read
printf '%s\n' "$input" > "$HOME/.claude/.current-session.json" 2>/dev/null

fi
