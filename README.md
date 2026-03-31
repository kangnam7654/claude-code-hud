# Claude Code HUD

A custom status line for Claude Code that displays real-time usage metrics at a glance.

[한국어](docs/README.ko.md) | [日本語](docs/README.ja.md) | [中文](docs/README.zh.md)

## What It Looks Like

```
Opus 4.6 (1M context) | 5m 0s (api:3m 0s) | $1.23 | d:$4.56 m:$78.90 | in:45.2K out:12.8K
ctx  [███████░░░░░░░░░░░░░] 35%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| Line | Content |
|------|---------|
| 1 | Model, session time (API time), session cost, daily/monthly cumulative cost, I/O tokens |
| 2 | Context window usage bar |
| 3 | 5-hour plan limit usage + reset timer |
| 4 | Weekly plan limit usage + reset timer |

- Bar colors: green (<50%) → yellow (50-79%) → red (80%+)
- Session cost: current session only (yellow)
- `d:` / `m:`: cumulative cost from past completed sessions (daily / monthly)

## Install

### macOS / Linux

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

To uninstall: `./install.sh --uninstall`

### Windows (PowerShell 7+)

```powershell
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud\win
.\install.ps1
```

To uninstall: `.\install.ps1 -Uninstall`

Both installers configure `~/.claude/settings.json` automatically. Restart Claude Code after install.

## How It Works

### Status Line (`statusline.sh`)

Reads session JSON from Claude Code via stdin and renders a multi-line dashboard:
- Session metrics (cost, time, tokens)
- Context window usage bar
- Plan usage bars with reset timers (from cached API data)
- Cumulative daily/monthly costs from past sessions (from `usage-log.jsonl`)
- Saves a session snapshot on each refresh for the SessionEnd hook

### Plan Usage (`fetch-plan-usage.sh`)

- Calls `api.anthropic.com/api/oauth/usage` using OAuth token
- Token source: `~/.claude/.credentials.json` or macOS Keychain
- 30-second cache (`~/.claude/plan-usage-cache.json`) so the status line stays fast
- Auto-refreshes in background when cache is stale

### Session Logging (`log-session.sh`)

- SessionEnd hook that reads the session snapshot written by `statusline.sh`
- Logs cost/token/duration metrics to `~/.claude/usage-log.jsonl`
- Cumulative totals are tracked across all projects globally

## Files

```
statusline.sh          # Main HUD script (reads JSON from stdin, renders output)
fetch-plan-usage.sh    # OAuth API plan usage fetcher + background cache
log-session.sh         # SessionEnd hook - logs session metrics to JSONL
install.sh             # Install/uninstall script (macOS/Linux)
lib/hud-utils.sh       # Shared utility functions (sourced by statusline.sh)
win/                   # Windows PowerShell port (statusline, fetch, log, install)
test/                  # BATS test suite (35 tests)
```

## Testing

```bash
./test/bats/bin/bats test/*.bats
```

## Requirements

- Claude Code (Max plan)
- macOS/Linux: `jq`, `curl`, `bc`
- Windows: PowerShell 7+ (`winget install Microsoft.PowerShell`)

## License

[MIT](LICENSE)
