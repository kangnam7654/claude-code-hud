#!/bin/bash
# Claude Code SessionEnd Hook - Logs session metrics to usage-log.jsonl
# Receives session JSON via stdin

LOG_FILE="$HOME/.claude/usage-log.jsonl"
input=$(cat)

# Extract fields and append as a single JSONL line
echo "$input" | jq -c '{
  timestamp: (now | todate),
  date: (now | strftime("%Y-%m-%d")),
  session_id: .session_id,
  model: .model.id,
  cost_usd: (.cost.total_cost_usd // 0),
  duration_ms: (.cost.total_duration_ms // 0),
  api_duration_ms: (.cost.total_api_duration_ms // 0),
  input_tokens: (.context_window.total_input_tokens // 0),
  output_tokens: (.context_window.total_output_tokens // 0)
}' >> "$LOG_FILE"
