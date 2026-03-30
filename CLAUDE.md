# Claude Code HUD

## Project Overview

Shell script project that displays usage metrics in Claude Code's status line.
Pure bash scripts only — no server, no build step.

## Architecture

```
statusline.sh        <- Parses session JSON from stdin, renders HUD output
fetch-plan-usage.sh  <- Fetches plan usage via OAuth API, caches to ~/.claude/ (30s TTL)
log-session.sh       <- SessionEnd hook, appends session metrics to JSONL
install.sh           <- Creates symlinks + configures settings.json
lib/hud-utils.sh     <- Pure utility functions (sourced by statusline.sh)
```

- All scripts are symlinked into `~/.claude/`
- Connected to Claude Code via `statusLine` and `hooks.SessionEnd` in settings.json
- Plan usage refreshes in background + cache so status line stays fast

## Key Paths (runtime)

- `~/.claude/settings.json` — Claude Code settings
- `~/.claude/.credentials.json` — OAuth token (for plan usage API)
- `~/.claude/usage-log.jsonl` — Per-session cost log
- `~/.claude/plan-usage-cache.json` — Plan usage cache (30s TTL)

## Conventions

- Language: Bash (POSIX-leaning, minimize bashisms)
- External deps: `jq`, `curl`, `bc` only
- Colors: Raw ANSI escape codes (no tput)
- README: English as default, translations in `docs/README.{ko,ja,zh}.md`
- Tests: BATS (bats-core) — run with `./test/bats/bin/bats test/*.bats`

## When Editing

- Test statusline.sh changes in a live Claude Code session (reads JSON from stdin)
- Run `./test/bats/bin/bats test/*.bats` after any change
- Validate syntax with `bash -n <script>.sh`
- When adding a new script, also add it to the `LINKS` array in install.sh
