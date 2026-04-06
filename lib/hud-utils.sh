#!/bin/bash
# Claude Code HUD - Pure utility functions (sourceable library)
# Source this file; do not execute directly.
#
# Note: color_by_pct() depends on global variables $RED, $YELLOW, $GREEN
# being defined by the caller before use.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This file should be sourced, not executed directly." >&2
    exit 1
fi

color_by_pct() {
    local pct=${1:-0}
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    if [ "$pct" -ge 80 ]; then echo "$RED"
    elif [ "$pct" -ge 50 ]; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

make_bar() {
    local pct=${1:-0} width=${2:-20}
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    local filled=$((pct * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$((width - filled))
    printf "%${filled}s" | sed 's/ /█/g'
    printf "%${empty}s" | sed 's/ /░/g'
}

format_tokens() {
    local n=${1:-0}
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if [ "$n" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
    elif [ "$n" -ge 1000 ]; then
        printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
    else
        printf "%d" "$n"
    fi
}

format_time() {
    local ms=${1:-0}
    [[ "$ms" =~ ^[0-9]+$ ]] || ms=0
    local total_sec=$((ms / 1000))
    local hrs=$((total_sec / 3600))
    local mins=$(((total_sec % 3600) / 60))
    local secs=$((total_sec % 60))
    if [ "$hrs" -gt 0 ]; then printf "%dh %dm" "$hrs" "$mins"
    elif [ "$mins" -gt 0 ]; then printf "%dm %ds" "$mins" "$secs"
    else printf "%ds" "$secs"; fi
}

format_cost() {
    local cost=${1:-0}
    local int_part
    int_part=$(echo "$cost" | cut -d. -f1)
    if [ "${int_part:-0}" -ge 1 ] 2>/dev/null; then printf '$%.2f' "$cost"
    else printf '$%.4f' "$cost"; fi
}

# Parse ISO 8601 timestamp to epoch (cross-platform: GNU date + BSD date)
iso_to_epoch() {
    local ts=$1
    if [ -z "$ts" ]; then return 1; fi
    # GNU date (Linux) — handles ISO 8601 natively
    date -d "$ts" +%s 2>/dev/null && return
    # BSD date (macOS) — must handle timezone offset manually
    local tz_offset_sec=0
    if [[ "$ts" =~ ([+-])([0-9]{2}):([0-9]{2})$ ]]; then
        local sign="${BASH_REMATCH[1]}" tz_h="${BASH_REMATCH[2]}" tz_m="${BASH_REMATCH[3]}"
        tz_offset_sec=$(( (10#$tz_h * 3600) + (10#$tz_m * 60) ))
        [ "$sign" = "-" ] && tz_offset_sec=$((-tz_offset_sec))
    fi
    # Strip fractional seconds and timezone suffix, parse as UTC
    local clean
    clean=$(echo "$ts" | sed 's/\.[0-9]*//' | sed 's/Z$//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//')
    local epoch
    epoch=$(date -juf "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null) || return 1
    echo $((epoch - tz_offset_sec))
}

# Format ISO timestamp to "Xh Ym" or "Xd Yh" remaining
format_remaining() {
    local reset_at=$1
    if [ -z "$reset_at" ] || [ "$reset_at" = "null" ]; then
        echo "?"
        return
    fi
    local reset_epoch
    reset_epoch=$(iso_to_epoch "$reset_at") || true
    local now_epoch
    now_epoch=$(date +%s)
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
