# Claude Code HUD

A custom status line for Claude Code that displays real-time usage metrics at a glance.

[한국어](docs/README.ko.md) | [日本語](docs/README.ja.md) | [中文](docs/README.zh.md)

## What It Looks Like

```
Opus 4.6 | 13m 28s (api:8m 41s) | $2.07 | d:$2.07 m:$2.07 | in:88.9K out:26.7K
ctx  [█████░░░░░░░░░░░░░░░] 29%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| Line | Content |
|------|---------|
| 1 | Model, session time (API time), session cost, daily/monthly cost, I/O tokens |
| 2 | Context window usage bar |
| 3 | 5-hour plan limit usage + reset timer |
| 4 | Weekly plan limit usage + reset timer |

Bar colors: green (<50%) → yellow (50-79%) → red (80%+)

## Install

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

This automatically creates symlinks and configures `~/.claude/settings.json`. Restart Claude Code after install.

To uninstall:

```bash
./install.sh --uninstall
```

## How It Works

### Status Line (`statusline.sh`)

Reads session JSON from Claude Code via stdin and renders a multi-line dashboard with:
- Session metrics (cost, time, tokens)
- Context window usage bar
- Plan usage bars with reset timers (from cached API data)
- Cumulative daily/monthly costs (from session log)

### Plan Usage (`fetch-plan-usage.sh`)

- Calls `api.anthropic.com/api/oauth/usage` using OAuth token from `~/.claude/.credentials.json`
- 30-second cache (`/tmp/claude-plan-usage.json`) so the status line stays fast
- Auto-refreshes in background when cache is stale

### Session Logging (`log-session.sh`)

- SessionEnd hook that logs cost/token metrics to `~/.claude/usage-log.jsonl`
- Status line sums current session + past sessions for daily/monthly totals

## Files

```
install.sh             # Install/uninstall script
statusline.sh          # Main HUD script (runs in status line)
fetch-plan-usage.sh    # Anthropic OAuth API plan usage fetcher + cache
log-session.sh         # SessionEnd hook - logs session metrics to JSONL
```

## Requirements

- Claude Code (Max plan)
- `jq`, `curl`, `bc`
