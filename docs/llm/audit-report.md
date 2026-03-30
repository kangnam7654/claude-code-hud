# Audit Report: claude-code-hud

## Gate Verdict

```yaml
step: "audit-gate"
agent: "cto"
status: "PARTIAL"
timestamp: "2026-03-30T00:00:00Z"
decision: "PARTIAL"
reason: >
  Architecture PASS (8.20) confirms sound design. Code quality (6.15) and
  security (7.20) have fixable issues that do not require redesign. Test
  coverage (0.40) is the critical gap but structurally addressable. Repo
  health gaps (7.10) are low-effort wins. Proceed with scoped improvements
  -- no architecture rewrite needed.
scope: "Safety/correctness hardening, testability extraction, basic test suite, repo health essentials"
next_step: "design-doc for improvement implementation"
```

**PARTIAL** means: proceed to improvements, but restrict scope to the items listed below. No architecture rewrite. No new external dependencies beyond bats-core (test only).

---

## Baseline Scores

| Area | Score | Threshold | Result |
|------|------:|----------:|--------|
| Code Quality | 6.15 | 7.0 | FAIL |
| Security | 7.20 | 7.5 | FAIL |
| Architecture | 8.20 | 7.0 | PASS |
| Test Coverage | 0.40 | 5.0 | FAIL |
| Repo Health | 7.10 | 7.0 | FAIL |
| **Weighted Overall** | **5.81** | **7.0** | **FAIL** |

Weighted formula: Code Quality 0.25 + Security 0.20 + Architecture 0.15 + Test Coverage 0.25 + Repo Health 0.15 = `6.15*0.25 + 7.20*0.20 + 8.20*0.15 + 0.40*0.25 + 7.10*0.15 = 1.5375 + 1.44 + 1.23 + 0.10 + 1.065 = 5.3725` (rounded 5.37).

---

## Scope Definition

### IN scope

1. Safety and correctness fixes (silent failures, input validation, shell injection prevention)
2. Security hardening (symlink attacks, TLS verification)
3. Testability refactor: extract pure functions into sourceable library, add source-guard
4. Basic BATS test suite covering extracted functions
5. Repo health essentials: CI with shellcheck + bats, LICENSE, .shellcheckrc, .editorconfig

### OUT of scope -- DO NOT implement these

- Full architecture rewrite (separation of concerns in statusline.sh into multiple files)
- Log rotation for usage-log.jsonl (operational concern, not correctness)
- Config file mechanism / environment variable extraction (extensibility, low priority for ~350 LOC)
- Color variable deduplication (DRY violation is cosmetic for 7 lines across 2 files)
- New features or output format changes
- Performance optimization (jq consolidation) -- architecture PASS already, not blocking

---

## Prioritized Improvements

### P0: Safety/Correctness (fix first -- silent data loss and injection risks)

| ID | Finding | File(s) | What to fix | Effort |
|----|---------|---------|-------------|--------|
| P0-1 | C-1: log-session.sh has no `set -e`, no jq error handling, no directory guard | `log-session.sh` | Add `set -euo pipefail`. Guard that `$LOG_FILE` parent directory exists (`mkdir -p`). Validate jq output before appending: capture jq result, check non-empty, then append. | S |
| P0-2 | C-2: statusline.sh has no stdin validation | `statusline.sh` | After `input=$(cat)`, validate: if `$input` is empty or not valid JSON (`echo "$input" \| jq -e . >/dev/null 2>&1`), print a fallback "no data" status line and exit 0. | S |
| P0-3 | C-3: Shell variables in jq filter string (lines 164-165) | `statusline.sh` | Replace `\"$TODAY\"` and `\"$MONTH\"` with jq `--arg today "$TODAY" --arg month "$MONTH"` and use `$today`/`$month` inside the jq filter. Prevents injection if date format ever changes or is externally influenced. | S |
| P0-4 | FILE-1: Symlink attack on /tmp/claude-plan-usage.json | `fetch-plan-usage.sh` | Move cache to `$HOME/.claude/plan-usage-cache.json` (user-private directory). Update `PLAN_CACHE` in both `statusline.sh` and `fetch-plan-usage.sh`. Also update `install.sh` uninstall section to clean new path. | S |
| P0-5 | M-1: Unvalidated jq output in arithmetic (line 135) | `statusline.sh` | Wrap CACHE_AGE arithmetic: default jq output to 0 if non-numeric. Pattern: `local ts; ts=$(jq -r '.timestamp // 0' "$PLAN_CACHE" 2>/dev/null); [[ "$ts" =~ ^[0-9]+$ ]] \|\| ts=0` | S |
| P0-6 | M-2: $COST passed to bc without numeric validation | `statusline.sh` | After parsing COST from jq, validate: `[[ "$COST" =~ ^[0-9]*\.?[0-9]+$ ]] \|\| COST=0`. Apply same pattern to DAILY_TOTAL and MONTHLY_TOTAL before bc calls on lines 169-170. | S |
| P0-7 | CRED-1: curl -s suppresses TLS errors | `fetch-plan-usage.sh` | Replace `curl -s` with `curl -sS --fail` to surface TLS and HTTP errors. Capture stderr: `RESPONSE=$(curl -sS --fail --max-time 10 ... 2>&1)`. On curl failure ($? != 0), write error to cache with the curl error message. | S |

**Total P0 effort: 7 small items. Estimated: 1 implementation session.**

### P1: Testability + Test Suite (fix second -- enables all future maintenance)

| ID | Finding | File(s) | What to fix | Effort |
|----|---------|---------|-------------|--------|
| P1-1 | Extract pure functions from statusline.sh into sourceable library | `lib/hud-utils.sh` (new), `statusline.sh` | Create `lib/hud-utils.sh` containing: `color_by_pct`, `make_bar`, `format_tokens`, `format_time`, `format_cost`, `iso_to_epoch`, `format_remaining`. Add source-guard to lib file (`[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1`). In statusline.sh, add `source "$(dirname "$0")/lib/hud-utils.sh"`. | M |
| P1-2 | Add source-guard to statusline.sh | `statusline.sh` | Wrap `input=$(cat)` and all non-function code in a main-guard: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi`. This allows sourcing statusline.sh in tests without blocking on stdin. After P1-1 this guard only protects the main orchestration block. | S |
| P1-3 | Install BATS test framework | `test/` (new dir), `test/test_helper/` | Add bats-core as git submodule or document install instruction. Create `test/test_helper/` with bats-support and bats-assert. Add `test/bats-helpers.bash` that sources `lib/hud-utils.sh`. | S |
| P1-4 | Write P0 function tests (14 cases) | `test/test_format_functions.bats` | Test each extracted function: `format_tokens` (4 cases: 0, 999, 1500, 2500000), `format_time` (4 cases: 0ms, 5000ms, 125000ms, 7200000ms), `format_cost` (3 cases: 0, 0.0012, 2.50), `color_by_pct` (3 cases: 30, 60, 90). | M |
| P1-5 | Write error handling tests (7 cases) | `test/test_error_handling.bats` | Test: empty stdin fallback, invalid JSON stdin, missing cache file, corrupt cache file, non-numeric token values, non-numeric cost values, missing plan cache. | M |
| P1-6 | Write timestamp tests (6 cases) | `test/test_timestamp.bats` | Test `iso_to_epoch` and `format_remaining`: valid ISO timestamp, Z suffix, +offset suffix, null input, empty input, past timestamp ("soon" output). | S |
| P1-7 | Add install.sh to LINKS array and update CLAUDE.md | `install.sh`, `CLAUDE.md` | Add `lib/hud-utils.sh` to the symlink or source path resolution so it works from `~/.claude/`. Update CLAUDE.md architecture section to mention `lib/hud-utils.sh`. | S |

**Total P1 effort: 3M + 4S items. Estimated: 1-2 implementation sessions.**

### P2: Repo Health + Remaining Hardening (fix last)

| ID | Finding | File(s) | What to fix | Effort |
|----|---------|---------|-------------|--------|
| P2-1 | No CI pipeline | `.github/workflows/ci.yml` (new) | Create GitHub Actions workflow: trigger on push/PR to main. Steps: install jq/bats, run `shellcheck *.sh lib/*.sh`, run `bats test/`. | S |
| P2-2 | No .shellcheckrc | `.shellcheckrc` (new) | Create with: `shell=bash`, `enable=all`, `disable=SC2034` (unused color vars are intentional). | S |
| P2-3 | No LICENSE | `LICENSE` (new) | Add MIT license (consistent with the README's implied open-source nature). Confirm with user before creating. | S |
| P2-4 | Minimal .gitignore | `.gitignore` | Add: `/tmp/`, `*.bak`, `.DS_Store`, `test/test_results/`. | S |
| P2-5 | No .editorconfig | `.editorconfig` (new) | Create with: `indent_style = space`, `indent_size = 4` for .sh files, `end_of_line = lf`, `insert_final_newline = true`. | S |
| P2-6 | M-4: mktemp tempfiles not cleaned up in install.sh | `install.sh` | Add `trap 'rm -f "$tmp"' EXIT` at top of install function scope (after first mktemp). Or use a single tmp variable and clean up in trap. | S |
| P2-7 | M-8: `readlink -f` is GNU-only (line 139) | `install.sh` | Replace with POSIX-compatible resolution: `realpath` (available on macOS 13+) with `readlink` fallback, or inline: `(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")`. | S |
| P2-8 | M-6: SC2155 `local var=$(cmd)` swallows exit code | `statusline.sh` (multiple), `install.sh` | Split declarations: `local var; var=$(cmd)`. Apply to: statusline.sh line 88 (`iso_to_epoch`), line 77 (`format_cost`), install.sh line 55-56 (uninstall tmp). | S |
| P2-9 | M-5: `[ ... ] 2>/dev/null` masks arithmetic errors | `statusline.sh` | In `color_by_pct` (lines 39-41): replace `2>/dev/null` with explicit numeric validation before comparison. Pattern: `[[ "$pct" =~ ^[0-9]+$ ]] \|\| pct=0`. | S |
| P2-10 | FILE-2: No symlink guard on settings.json before mv | `install.sh` | Before `mv "$tmp" "$SETTINGS_FILE"`, verify `$SETTINGS_FILE` is a regular file (not a symlink): `if [ -L "$SETTINGS_FILE" ]; then error "settings.json is a symlink -- aborting"; exit 1; fi`. | S |

**Total P2 effort: 10 small items. Estimated: 1 implementation session.**

---

## Implementation Order

```
Phase 1 (P0): Safety/correctness
  P0-1 through P0-7 (all independent, can be done in any order)
  Commit after all P0 items pass manual smoke test

Phase 2 (P1): Testability
  P1-1 (extract lib) -> P1-2 (source-guard) -> P1-3 (bats setup)
  -> P1-4, P1-5, P1-6 (tests, parallelizable) -> P1-7 (update docs)
  Commit after bats test suite passes

Phase 3 (P2): Repo health + remaining hardening
  P2-1 (CI) depends on P1-3 (bats must exist)
  P2-2 through P2-10 are independent
  Commit after CI workflow passes on push
```

---

## Target Scores After Improvements

| Area | Current | Target | Delta |
|------|--------:|-------:|------:|
| Code Quality | 6.15 | 8.0+ | +1.85 |
| Security | 7.20 | 8.5+ | +1.30 |
| Architecture | 8.20 | 8.20 | 0 (no arch changes) |
| Test Coverage | 0.40 | 7.0+ | +6.60 |
| Repo Health | 7.10 | 8.5+ | +1.40 |
| **Weighted Overall** | **5.37** | **7.8+** | **+2.43** |

---

## Constraints for Implementation

1. Pure bash only. No Python, no Node.js, no build step.
2. External runtime deps remain jq, curl, bc only. BATS is test-only.
3. No new scripts in the root directory except `lib/hud-utils.sh` (subdirectory).
4. All fixes must be backward-compatible with existing `~/.claude/settings.json` configurations.
5. `statusline.sh` must continue to read JSON from stdin and output ANSI-colored lines to stdout.
6. Cache file path change (P0-4) requires updating both producer (`fetch-plan-usage.sh`) and consumer (`statusline.sh`) atomically in the same commit.
7. Each phase (P0, P1, P2) should be a separate commit for clean rollback.
