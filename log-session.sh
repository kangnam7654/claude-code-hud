#!/bin/bash
# Claude Code SessionEnd Hook - Logs session metrics to usage-log.jsonl
# Reads session data from snapshot file written by statusline.sh
# (SessionEnd hook stdin only contains minimal metadata, not cost/token data)

set -euo pipefail

LOG_FILE="$HOME/.claude/usage-log.jsonl"
SNAPSHOT="$HOME/.claude/.current-session.json"
mkdir -p "$(dirname "$LOG_FILE")"

# Read session data from statusline snapshot
if [ ! -f "$SNAPSHOT" ]; then
    exit 0
fi

input=$(<"$SNAPSHOT")

# Skip if empty
if [ -z "$input" ]; then
    exit 0
fi

# Extract fields and append as a single JSONL line
line=$(printf '%s\n' "$input" | jq -c '{
  timestamp: (now | todate),
  date: (now | strftime("%Y-%m-%d")),
  session_id: .session_id,
  model: .model.id,
  cost_usd: (.cost.total_cost_usd // 0),
  duration_ms: (.cost.total_duration_ms // 0),
  api_duration_ms: (.cost.total_api_duration_ms // 0),
  input_tokens: (.context_window.total_input_tokens // 0),
  output_tokens: (.context_window.total_output_tokens // 0)
}' 2>/dev/null) || true

if [ -n "$line" ]; then
    echo "$line" >> "$LOG_FILE"
fi

# Clean up snapshot
rm -f "$SNAPSHOT"
