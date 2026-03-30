# Design Spec: claude-code-hud Improvement

Audit baseline: overall 5.37/10 (PARTIAL gate). Target: 7.8+/10.
Audit report: `/Users/kangnam/projects/claude-code-hud/docs/llm/audit-report.md`

---

## 1. 목적 (Purpose)

**Problem:** claude-code-hud 4개 스크립트(515 LOC)가 입력 유효성 검사 부재, /tmp 심링크 공격 취약점, 산술 오류 무시, 테스트 0건, CI 부재로 인해 무결성 점수 5.37/10이다.

**Completion criteria (모두 충족해야 완료):**
1. `set -euo pipefail` + 모든 jq/bc 입력에 숫자 유효성 검사 적용 (P0)
2. stdin 빈 값/비정상 JSON에 대해 fallback 출력 후 exit 0 (P0)
3. 캐시 파일이 `/tmp/`에서 `$HOME/.claude/`로 이동 (P0)
4. `lib/hud-utils.sh`에 7개 순수 함수 추출 완료, source-guard 적용 (P1)
5. BATS 테스트 27건 이상, 전부 PASS (P1)
6. GitHub Actions CI가 shellcheck + bats를 실행하고 PASS (P2)
7. `.shellcheckrc`, `.editorconfig`, LICENSE 파일 존재 (P2)

---

## 2. 파일 변경 목록 (File Change List)

### 수정 대상 (기존 파일)

| 파일 경로 | 변경 요약 |
|-----------|----------|
| `statusline.sh` | stdin 유효성 검사 추가, jq --arg로 변수 주입 제거, 숫자 유효성 검사 추가, `lib/hud-utils.sh` source, main-guard 래핑, PLAN_CACHE 경로 변경, SC2155 수정 |
| `fetch-plan-usage.sh` | CACHE_FILE 경로를 `$HOME/.claude/plan-usage-cache.json`으로 변경, `curl -sS --fail` 적용, 에러 메시지 보존 |
| `log-session.sh` | `set -euo pipefail` 추가, 디렉토리 guard, jq 출력 유효성 검사 후 append |
| `install.sh` | PLAN_CACHE 경로 변경, mktemp trap 추가, `readlink -f` POSIX 호환 대체, settings.json 심링크 guard, LINKS 배열에 lib/ 경로 추가, SC2155 수정 |
| `.gitignore` | `/tmp/`, `*.bak`, `.DS_Store`, `test/test_results/` 추가 |
| `CLAUDE.md` | Architecture 섹션에 `lib/hud-utils.sh` 언급 추가 |

### 신규 생성 대상

| 파일 경로 | 내용 |
|-----------|------|
| `lib/hud-utils.sh` | statusline.sh에서 추출한 7개 순수 함수 + source-guard |
| `test/test_format_functions.bats` | format_tokens, format_time, format_cost, color_by_pct 테스트 14건 |
| `test/test_error_handling.bats` | stdin fallback, 비정상 JSON, 캐시 부재 등 에러 처리 테스트 7건 |
| `test/test_timestamp.bats` | iso_to_epoch, format_remaining 테스트 6건 |
| `test/test_helper/bats-helpers.bash` | lib/hud-utils.sh source + 공통 setup/teardown |
| `.github/workflows/ci.yml` | shellcheck + bats GitHub Actions 워크플로우 |
| `.shellcheckrc` | shell=bash, enable=all, disable=SC2034 |
| `.editorconfig` | indent_style=space, indent_size=4 for *.sh |
| `LICENSE` | MIT 라이선스 (사용자 확인 후 생성) |

---

## 3. 구현 순서 (Implementation Order)

### Phase 1: P0 -- Safety/Correctness (커밋 1)

모든 P0 항목을 완료한 뒤 수동 스모크 테스트를 수행하고 단일 커밋으로 만들어라.

**Step 1: log-session.sh 안전성 강화 (P0-1)**
- 파일: `log-session.sh`
- 라인 1-2 사이에 `set -euo pipefail` 삽입하라.
- `input=$(cat)` 후에 빈 입력 guard를 추가하라:
  ```bash
  if [ -z "$input" ]; then
      exit 0
  fi
  ```
- `LOG_FILE` 부모 디렉토리가 없으면 생성하라:
  ```bash
  mkdir -p "$(dirname "$LOG_FILE")"
  ```
- jq 출력을 변수에 캡처하고 비어있지 않은 경우에만 append하라:
  ```bash
  local line
  line=$(echo "$input" | jq -c '{...}' 2>/dev/null)
  if [ -n "$line" ]; then
      echo "$line" >> "$LOG_FILE"
  fi
  ```

**Step 2: statusline.sh stdin 유효성 검사 (P0-2)**
- 파일: `statusline.sh`
- 라인 7 (`input=$(cat)`) 직후에 아래를 삽입하라:
  ```bash
  if [ -z "$input" ] || ! echo "$input" | jq -e . >/dev/null 2>&1; then
      echo "HUD: no data"
      exit 0
  fi
  ```
- fallback 출력은 plain text (ANSI 코드 없음)로 하라. Claude Code statusLine이 이를 안전하게 표시한다.

**Step 3: statusline.sh jq --arg 주입 방지 (P0-3)**
- 파일: `statusline.sh`
- 현재 라인 164-165:
  ```bash
  DAILY_TOTAL=$(jq -rs "[.[] | select(.date == \"$TODAY\") | .cost_usd] | add // 0" "$LOG_FILE")
  MONTHLY_TOTAL=$(jq -rs "[.[] | select(.date | startswith(\"$MONTH\")) | .cost_usd] | add // 0" "$LOG_FILE")
  ```
- 다음으로 교체하라:
  ```bash
  DAILY_TOTAL=$(jq -rs --arg today "$TODAY" '[.[] | select(.date == $today) | .cost_usd] | add // 0' "$LOG_FILE")
  MONTHLY_TOTAL=$(jq -rs --arg month "$MONTH" '[.[] | select(.date | startswith($month)) | .cost_usd] | add // 0' "$LOG_FILE")
  ```
- jq 필터를 작은따옴표(single-quote)로 감싸라. `$today`, `$month`는 jq 변수이다.

**Step 4: 캐시 파일 경로 이동 (P0-4)**
- 변경 대상 파일 3개를 동시에 수정하라:
  - `fetch-plan-usage.sh` 라인 8: `CACHE_FILE="/tmp/claude-plan-usage.json"` --> `CACHE_FILE="$HOME/.claude/plan-usage-cache.json"`
  - `statusline.sh` 라인 19: `PLAN_CACHE="/tmp/claude-plan-usage.json"` --> `PLAN_CACHE="$HOME/.claude/plan-usage-cache.json"`
  - `install.sh` 라인 14: `PLAN_CACHE="/tmp/claude-plan-usage.json"` --> `PLAN_CACHE="$HOME/.claude/plan-usage-cache.json"`
- 3개 파일의 변수명은 각각 유지하라 (fetch: `CACHE_FILE`, statusline: `PLAN_CACHE`, install: `PLAN_CACHE`).

**Step 5: CACHE_AGE 산술 안전성 (P0-5)**
- 파일: `statusline.sh`
- 현재 라인 135:
  ```bash
  CACHE_AGE=$(( $(date +%s) - $(jq -r '.timestamp // 0' "$PLAN_CACHE" 2>/dev/null || echo 0) ))
  ```
- 다음으로 교체하라:
  ```bash
  local cache_ts
  cache_ts=$(jq -r '.timestamp // 0' "$PLAN_CACHE" 2>/dev/null || echo 0)
  [[ "$cache_ts" =~ ^[0-9]+$ ]] || cache_ts=0
  CACHE_AGE=$(( $(date +%s) - cache_ts ))
  ```
- 주의: `local` 키워드는 함수 내부에서만 유효하다. statusline.sh의 이 코드는 함수 밖 (top-level)에 있으므로 `local` 대신 일반 변수를 사용하라:
  ```bash
  cache_ts=$(jq -r '.timestamp // 0' "$PLAN_CACHE" 2>/dev/null || echo 0)
  [[ "$cache_ts" =~ ^[0-9]+$ ]] || cache_ts=0
  CACHE_AGE=$(( $(date +%s) - cache_ts ))
  ```

**Step 6: COST/DAILY_TOTAL/MONTHLY_TOTAL bc 입력 검사 (P0-6)**
- 파일: `statusline.sh`
- COST 파싱(라인 11) 직후에 아래를 삽입하라:
  ```bash
  [[ "$COST" =~ ^[0-9]*\.?[0-9]+$ ]] || COST=0
  ```
- DAILY_TOTAL, MONTHLY_TOTAL 파싱(Step 3에서 수정한 jq 라인들) 직후에 각각 동일 패턴을 삽입하라:
  ```bash
  [[ "$DAILY_TOTAL" =~ ^[0-9]*\.?[0-9]+$ ]] || DAILY_TOTAL=0
  [[ "$MONTHLY_TOTAL" =~ ^[0-9]*\.?[0-9]+$ ]] || MONTHLY_TOTAL=0
  ```
- 이 검증 라인은 bc 호출(라인 169-170)보다 반드시 위에 위치해야 한다.

**Step 7: curl 에러 표면화 (P0-7)**
- 파일: `fetch-plan-usage.sh`
- 현재 라인 32-36의 curl 호출:
  ```bash
  RESPONSE=$(curl -s --max-time 10 \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      ...
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
  ```
- 다음으로 교체하라:
  ```bash
  RESPONSE=$(curl -sS --fail --max-time 10 \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "Content-Type: application/json" \
      "https://api.anthropic.com/api/oauth/usage" 2>&1)
  curl_exit=$?
  if [ $curl_exit -ne 0 ]; then
      echo "{\"error\":\"curl failed (exit $curl_exit): $(echo "$RESPONSE" | head -c 200)\",\"timestamp\":$(date +%s)}" > "$CACHE_FILE"
      exit 1
  fi
  ```
- `2>/dev/null`을 `2>&1`로 변경하여 TLS/HTTP 에러 메시지를 캡처하라.
- 기존 38-41번 라인의 빈 RESPONSE 체크 블록은 curl_exit 체크로 대체되므로 삭제하라.

### Phase 2: P1 -- Testability + Test Suite (커밋 2)

P1-1 -> P1-2 -> P1-3 순서로 진행하라. P1-4, P1-5, P1-6은 병렬 가능하다. P1-7은 마지막에 수행하라.

**Step 8: 순수 함수 추출 -- lib/hud-utils.sh 생성 (P1-1)**
- 파일: `lib/hud-utils.sh` (신규)
- `lib/` 디렉토리를 먼저 생성하라: `mkdir -p lib`
- statusline.sh에서 아래 7개 함수를 그대로 복사하라 (시그니처 변경 없음):
  1. `color_by_pct` (현재 라인 37-42)
  2. `make_bar` (현재 라인 44-51)
  3. `format_tokens` (현재 라인 53-62)
  4. `format_time` (현재 라인 64-73)
  5. `format_cost` (현재 라인 75-80)
  6. `iso_to_epoch` (현재 라인 83-91)
  7. `format_remaining` (현재 라인 94-111)
- 파일 상단에 shebang과 source-guard를 추가하라:
  ```bash
  #!/bin/bash
  # Claude Code HUD - Pure utility functions (sourceable library)
  # Source this file; do not execute directly.

  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
      echo "Error: This file should be sourced, not executed directly." >&2
      exit 1
  fi
  ```
- 함수 본문에서 P0 단계의 수정사항(P0-5의 numeric validation, P0-9의 pct validation 등)을 반영하라.
- ANSI 색상 변수(`$RED`, `$YELLOW`, `$GREEN`)는 lib 내에서 정의하지 마라. 이 함수들은 호출자(statusline.sh)가 이미 정의한 색상 변수를 사용한다. `color_by_pct`는 `$RED`, `$YELLOW`, `$GREEN` 전역 변수에 의존한다는 점을 주석으로 명시하라.

**Step 9: statusline.sh에서 함수 제거 및 source 추가 (P1-1 계속)**
- 파일: `statusline.sh`
- shebang 직후, `input=$(cat)` 이전에 아래를 추가하라:
  ```bash
  source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/lib/hud-utils.sh"
  ```
- macOS에서 `readlink -f` 실패 시 fallback으로 `${BASH_SOURCE[0]}` 그대로 사용한다. 심링크된 `~/.claude/statusline.sh`에서 실행 시 `readlink -f`가 원본 경로를 반환하므로 `lib/hud-utils.sh`를 올바르게 찾는다.
- 대안 (더 안전한 POSIX 호환 방식):
  ```bash
  _hud_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  source "${_hud_dir}/lib/hud-utils.sh"
  ```
- 이 POSIX 호환 방식을 채택하라 (의사결정 D2 참조).
- 라인 37-111의 7개 함수 정의를 statusline.sh에서 삭제하라.

**Step 10: statusline.sh main-guard 추가 (P1-2)**
- 파일: `statusline.sh`
- source 문 이후, `input=$(cat)` 부터 파일 끝까지를 main-guard로 래핑하라:
  ```bash
  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
      input=$(cat)
      # ... (기존 코드 전체)
  fi
  ```
- 이렇게 하면 테스트에서 `source statusline.sh`로 lib/hud-utils.sh를 간접 로드하지 않고, 직접 `source lib/hud-utils.sh`를 사용할 수 있다.
- 실제로 테스트에서는 `lib/hud-utils.sh`를 직접 source하므로 statusline.sh의 main-guard는 주로 방어적 용도이다.

**Step 11: BATS 테스트 프레임워크 설정 (P1-3)**
- `test/` 디렉토리를 생성하라.
- bats-core, bats-support, bats-assert를 git submodule로 추가하라:
  ```bash
  git submodule add https://github.com/bats-core/bats-core.git test/bats
  git submodule add https://github.com/bats-core/bats-support.git test/test_helper/bats-support
  git submodule add https://github.com/bats-core/bats-assert.git test/test_helper/bats-assert
  ```
- `test/test_helper/bats-helpers.bash` 파일을 생성하라:
  ```bash
  #!/bin/bash
  # Common test helper - sources lib and sets up assertions

  # Load bats helpers
  load 'bats-support/load'
  load 'bats-assert/load'

  # Define color variables that lib functions depend on
  RED='\033[31m'
  YELLOW='\033[33m'
  GREEN='\033[32m'

  # Source the library under test
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  source "${PROJECT_ROOT}/lib/hud-utils.sh"
  ```

**Step 12: format 함수 테스트 작성 (P1-4)**
- 파일: `test/test_format_functions.bats`
- 14 test cases:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-helpers'
}

# --- format_tokens ---
@test "format_tokens: 0 returns 0" {
    run format_tokens 0
    assert_output "0"
}

@test "format_tokens: 999 returns 999" {
    run format_tokens 999
    assert_output "999"
}

@test "format_tokens: 1500 returns 1.5K" {
    run format_tokens 1500
    assert_output "1.5K"
}

@test "format_tokens: 2500000 returns 2.5M" {
    run format_tokens 2500000
    assert_output "2.5M"
}

# --- format_time ---
@test "format_time: 0ms returns 0s" {
    run format_time 0
    assert_output "0s"
}

@test "format_time: 5000ms returns 5s" {
    run format_time 5000
    assert_output "5s"
}

@test "format_time: 125000ms returns 2m 5s" {
    run format_time 125000
    assert_output "2m 5s"
}

@test "format_time: 7200000ms returns 2h 0m" {
    run format_time 7200000
    assert_output "2h 0m"
}

# --- format_cost ---
@test "format_cost: 0 returns $0.0000" {
    run format_cost 0
    assert_output '$0.0000'
}

@test "format_cost: 0.0012 returns $0.0012" {
    run format_cost 0.0012
    assert_output '$0.0012'
}

@test "format_cost: 2.50 returns $2.50" {
    run format_cost 2.50
    assert_output '$2.50'
}

# --- color_by_pct ---
@test "color_by_pct: 30 returns GREEN" {
    run color_by_pct 30
    assert_output "$GREEN"
}

@test "color_by_pct: 60 returns YELLOW" {
    run color_by_pct 60
    assert_output "$YELLOW"
}

@test "color_by_pct: 90 returns RED" {
    run color_by_pct 90
    assert_output "$RED"
}
```

**Step 13: 에러 처리 테스트 작성 (P1-5)**
- 파일: `test/test_error_handling.bats`
- 7 test cases. 이 테스트들은 statusline.sh를 직접 실행(stdin 파이프)하여 통합 테스트한다:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-helpers'
    STATUSLINE="${PROJECT_ROOT}/statusline.sh"
}

@test "statusline: empty stdin outputs fallback" {
    run bash -c 'echo -n "" | "$0"' "$STATUSLINE"
    assert_output --partial "no data"
    assert_success
}

@test "statusline: invalid JSON outputs fallback" {
    run bash -c 'echo "not json" | "$0"' "$STATUSLINE"
    assert_output --partial "no data"
    assert_success
}

@test "statusline: missing plan cache does not fail" {
    # Ensure no cache file exists
    rm -f "$HOME/.claude/plan-usage-cache.json"
    run bash -c 'echo "{\"model\":{\"display_name\":\"test\"},\"cost\":{\"total_cost_usd\":0,\"total_duration_ms\":0,\"total_api_duration_ms\":0},\"context_window\":{\"used_percentage\":0,\"total_input_tokens\":0,\"total_output_tokens\":0}}" | "$0"' "$STATUSLINE"
    assert_success
}

@test "format_tokens: non-numeric input returns 0" {
    run format_tokens "abc"
    assert_output "0"
}

@test "format_time: non-numeric input returns 0s" {
    run format_time "abc"
    assert_output "0s"
}

@test "color_by_pct: empty input returns GREEN" {
    run color_by_pct ""
    assert_output "$GREEN"
}

@test "color_by_pct: non-numeric input returns GREEN" {
    run color_by_pct "abc"
    assert_output "$GREEN"
}
```

- 주의: `format_tokens`와 `format_time`에 비숫자 입력이 들어오면 0을 반환하도록 P0-9(M-5) 수정이 `lib/hud-utils.sh`에 반영되어야 한다. 함수 시그니처 섹션 참조.

**Step 14: 타임스탬프 테스트 작성 (P1-6)**
- 파일: `test/test_timestamp.bats`
- 6 test cases:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-helpers'
}

@test "iso_to_epoch: valid ISO timestamp returns epoch" {
    run iso_to_epoch "2026-01-01T00:00:00Z"
    assert_success
    # Should output a numeric epoch
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "iso_to_epoch: Z suffix handled" {
    run iso_to_epoch "2026-06-15T12:30:00Z"
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "iso_to_epoch: +offset suffix handled" {
    run iso_to_epoch "2026-06-15T12:30:00+09:00"
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "iso_to_epoch: null input fails" {
    run iso_to_epoch ""
    assert_failure
}

@test "format_remaining: null input returns ?" {
    run format_remaining "null"
    assert_output "?"
}

@test "format_remaining: past timestamp returns soon" {
    run format_remaining "2020-01-01T00:00:00Z"
    assert_output "soon"
}
```

**Step 15: install.sh에 lib/ 경로 추가 및 CLAUDE.md 업데이트 (P1-7)**
- 파일: `install.sh`
- LINKS 배열은 단일 파일 심링크 전용이므로 lib/ 디렉토리는 다른 방식으로 처리하라.
- 심링크 생성 루프(라인 128-162) 이전에 lib/ 디렉토리 심링크를 추가하라:
  ```bash
  # Symlink lib directory
  LIB_SRC="$SCRIPT_DIR/lib"
  LIB_DEST="$CLAUDE_DIR/lib"
  if [ -d "$LIB_SRC" ]; then
      if [ -L "$LIB_DEST" ] || [ ! -e "$LIB_DEST" ]; then
          ln -sfn "$LIB_SRC" "$LIB_DEST"
          info "lib/ -> $LIB_DEST"
      else
          warn "lib/ exists at $LIB_DEST but is not a symlink -- skipping"
      fi
  fi
  ```
- `ln -sfn`을 사용하라 (`-n`은 기존 심링크 디렉토리를 교체할 때 필요).
- 언인스톨 함수에도 lib 심링크 제거를 추가하라:
  ```bash
  # Remove lib symlink
  if [ -L "$CLAUDE_DIR/lib" ]; then
      rm "$CLAUDE_DIR/lib"
      info "Removed symlink: $CLAUDE_DIR/lib"
  fi
  ```
- 파일: `CLAUDE.md`
- Architecture 섹션의 파일 목록에 `lib/hud-utils.sh`를 추가하라:
  ```
  lib/hud-utils.sh     <- Pure utility functions (sourced by statusline.sh)
  ```

### Phase 3: P2 -- Repo Health + Remaining Hardening (커밋 3)

**Step 16: GitHub Actions CI (P2-1)**
- 파일: `.github/workflows/ci.yml`
- 디렉토리를 먼저 생성하라: `mkdir -p .github/workflows`
- 내용:
  ```yaml
  name: CI
  on:
    push:
      branches: [main]
    pull_request:
      branches: [main]

  jobs:
    lint-and-test:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
          with:
            submodules: recursive

        - name: Install dependencies
          run: |
            sudo apt-get update
            sudo apt-get install -y jq bc

        - name: Install shellcheck
          run: sudo apt-get install -y shellcheck

        - name: Run shellcheck
          run: shellcheck *.sh lib/*.sh

        - name: Run BATS tests
          run: ./test/bats/bin/bats test/*.bats
  ```

**Step 17: .shellcheckrc 생성 (P2-2)**
- 파일: `.shellcheckrc`
- 내용:
  ```
  shell=bash
  enable=all
  # SC2034: Unused variables - color variables are used by sourcing scripts
  disable=SC2034
  ```

**Step 18: LICENSE 생성 (P2-3)**
- 파일: `LICENSE`
- MIT 라이선스. 저작권자: 사용자에게 확인 후 결정하라. 기본값: `kangnam`.
- **구현자 주의: LICENSE 생성 전에 사용자에게 "MIT LICENSE를 kangnam 명의로 생성합니다. 확인하시겠습니까?" 라고 물어라.**

**Step 19: .gitignore 업데이트 (P2-4)**
- 파일: `.gitignore`
- 기존 내용 `*.json.tmp` 유지, 아래를 추가하라:
  ```
  *.bak
  .DS_Store
  test/test_results/
  ```
- `/tmp/`는 추가하지 마라 -- 이 프로젝트에 tmp/ 디렉토리는 없으며, 캐시는 이미 P0-4에서 ~/.claude/로 이동했다.

**Step 20: .editorconfig 생성 (P2-5)**
- 파일: `.editorconfig`
- 내용:
  ```
  root = true

  [*]
  end_of_line = lf
  insert_final_newline = true
  charset = utf-8

  [*.sh]
  indent_style = space
  indent_size = 4

  [*.bats]
  indent_style = space
  indent_size = 4

  [*.{yml,yaml}]
  indent_style = space
  indent_size = 2

  [Makefile]
  indent_style = tab
  ```

**Step 21: install.sh mktemp trap 추가 (P2-6)**
- 파일: `install.sh`
- settings.json 업데이트 섹션(라인 164 부근) 시작 전에 trap을 설정하라. 여러 mktemp 호출에 대해 하나의 cleanup 변수를 사용하라:
  ```bash
  _cleanup_files=()
  trap 'rm -f "${_cleanup_files[@]}"' EXIT
  ```
- 각 `tmp=$(mktemp)` 호출 직후에 `_cleanup_files+=("$tmp")`를 추가하라.
- 해당 위치: 라인 56 (uninstall 내), 라인 197, 라인 209 (install 내).

**Step 22: readlink -f POSIX 호환 교체 (P2-7)**
- 파일: `install.sh`
- 라인 139-140:
  ```bash
  existing=$(readlink -f "$dest")
  expected=$(readlink -f "$src")
  ```
- POSIX 호환 함수를 install.sh 상단(color 정의 후)에 추가하라:
  ```bash
  # POSIX-compatible readlink -f replacement
  resolve_path() {
      local path="$1"
      if command -v realpath &>/dev/null; then
          realpath "$path"
      else
          (cd "$(dirname "$path")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$path")")
      fi
  }
  ```
- 라인 139-140을 교체하라:
  ```bash
  existing=$(resolve_path "$dest")
  expected=$(resolve_path "$src")
  ```

**Step 23: settings.json 심링크 guard (P2-10)**
- 파일: `install.sh`
- settings.json 업데이트 섹션에서 `mv "$tmp" "$SETTINGS_FILE"` 호출 전에 (3곳 모두) 아래를 삽입하라:
  ```bash
  if [ -L "$SETTINGS_FILE" ]; then
      error "settings.json is a symlink -- aborting for safety"
      rm -f "$tmp"
      exit 1
  fi
  ```
- 3곳: 라인 189 (신규 생성 시에는 불필요 -- 파일이 없으므로), 라인 199, 라인 211.
- 실제로는 `jq ... > "$tmp" && mv "$tmp" "$SETTINGS_FILE"` 패턴의 mv 직전에 guard를 삽입한다.

**Step 24: SC2155 수정 (P2-8)**
- 파일: `statusline.sh`
- `format_cost` 함수 (lib/hud-utils.sh로 이동된 후):
  ```bash
  # Before (SC2155 violation):
  local int_part=$(echo "$cost" | cut -d. -f1)
  # After:
  local int_part
  int_part=$(echo "$cost" | cut -d. -f1)
  ```
- `iso_to_epoch` 함수 (lib/hud-utils.sh로 이동된 후):
  ```bash
  # Before:
  local clean=$(echo "$ts" | sed 's/Z$//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//')
  # After:
  local clean
  clean=$(echo "$ts" | sed 's/Z$//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//')
  ```
- `format_remaining` 함수:
  ```bash
  # Before:
  local reset_epoch=$(iso_to_epoch "$reset_at")
  local now_epoch=$(date +%s)
  # After:
  local reset_epoch
  reset_epoch=$(iso_to_epoch "$reset_at")
  local now_epoch
  now_epoch=$(date +%s)
  ```
- 파일: `install.sh` -- 라인 55-56 (uninstall 내):
  ```bash
  # Before:
  local tmp
  tmp=$(mktemp)
  # (이미 분리되어 있다면 변경 불필요)
  ```
  실제 코드를 확인하면 라인 55-56은 이미 `local tmp` + `tmp=$(mktemp)`로 분리되어 있으므로 변경 불필요하다.

**Step 25: color_by_pct 숫자 검증 (P2-9)**
- 파일: `lib/hud-utils.sh` (Step 8에서 생성)
- `color_by_pct` 함수에서 `2>/dev/null` 대신 명시적 숫자 검증을 사용하라:
  ```bash
  color_by_pct() {
      local pct=${1:-0}
      [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
      if [ "$pct" -ge 80 ]; then echo "$RED"
      elif [ "$pct" -ge 50 ]; then echo "$YELLOW"
      else echo "$GREEN"; fi
  }
  ```

---

## 4. 함수/API 시그니처 (Function/API Signatures)

### lib/hud-utils.sh에 추출되는 7개 함수

모든 함수는 stdout으로 결과를 출력한다. 실패 시 기본값을 출력하고 exit 0한다 (호출자가 `$()` subshell로 캡처).

```bash
# 사용률에 따른 ANSI 색상 코드를 반환한다.
# 전역 변수 $RED, $YELLOW, $GREEN에 의존한다.
# pct가 비숫자이면 0으로 간주한다.
color_by_pct(pct: string) -> stdout: string
  # pct >= 80 -> "$RED"
  # pct >= 50 -> "$YELLOW"
  # else      -> "$GREEN"

# 퍼센트 막대를 unicode block 문자로 렌더링한다.
# filled 영역은 '█', 빈 영역은 '░'를 사용한다.
make_bar(pct: string, width: int) -> stdout: string
  # pct가 비숫자이면 0으로 간주한다.
  # filled = min(pct * width / 100, width)

# 토큰 수를 K/M 접미사 형태로 포맷한다.
# n이 비숫자이면 "0"을 출력한다.
format_tokens(n: string) -> stdout: string
  # n >= 1000000 -> "X.XM"
  # n >= 1000    -> "X.XK"
  # else         -> "N"

# 밀리초 단위 시간을 사람이 읽을 수 있는 형태로 포맷한다.
# ms가 비숫자이면 "0s"를 출력한다.
format_time(ms: string) -> stdout: string
  # hrs > 0  -> "Xh Ym"
  # mins > 0 -> "Xm Xs"
  # else     -> "Xs"

# USD 비용을 포맷한다. 정수부 >= 1이면 소수점 2자리, 아니면 4자리.
# cost가 비숫자이면 "$0.0000"을 출력한다.
format_cost(cost: string) -> stdout: string
  # int_part >= 1 -> "$X.XX"
  # else          -> "$X.XXXX"

# ISO 8601 타임스탬프를 Unix epoch로 변환한다.
# GNU date와 BSD date(macOS) 모두 지원한다.
# 변환 실패 시 return 1 (아무것도 출력하지 않는다).
iso_to_epoch(ts: string) -> stdout: int | return 1

# ISO 타임스탬프까지 남은 시간을 "Xd Yh" 또는 "Xh Ym" 또는 "Xm" 형태로 포맷한다.
# reset_at이 null/빈 값이면 "?"를 출력한다.
# 이미 지난 시각이면 "soon"을 출력한다.
format_remaining(reset_at: string) -> stdout: string
```

### statusline.sh 신규 추가 코드

```bash
# source 경로 해석 (함수 아님, top-level 코드)
_hud_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${_hud_dir}/lib/hud-utils.sh"

# stdin 유효성 검사 (main-guard 내부, 함수 아님)
# 빈 입력 또는 비정상 JSON이면 "HUD: no data"를 출력하고 exit 0
```

### install.sh 신규 함수

```bash
# POSIX 호환 readlink -f 대체.
# realpath이 있으면 사용하고, 없으면 cd + pwd -P로 해석한다.
resolve_path(path: string) -> stdout: string
```

### log-session.sh 변경 사항

함수 추가 없음. 기존 스크립트에 `set -euo pipefail`, 입력 guard, jq 출력 검증을 추가한다.

---

## 5. 제약 조건 (Constraints)

1. **순수 bash만 사용하라.** Python, Node.js, 빌드 도구를 추가하지 마라.
2. **런타임 의존성은 jq, curl, bc만 허용한다.** BATS는 테스트 전용 의존성이다.
3. **기존 `~/.claude/settings.json` 구성과 하위 호환을 유지하라.** statusline.sh의 stdin JSON 형식과 stdout 출력 형식을 변경하지 마라.
4. **각 Phase(P0, P1, P2)는 별도 커밋이다.** P0 커밋 후 스모크 테스트, P1 커밋 후 BATS 전체 PASS, P2 커밋 후 shellcheck + BATS PASS를 검증하라.
5. **ANSI 색상 코드는 raw escape sequence를 그대로 사용하라.** tput을 도입하지 마라 (기존 Convention).
6. **root 디렉토리에 새 스크립트를 추가하지 마라.** 유틸리티는 `lib/` 하위에만 배치한다.
7. **lib/hud-utils.sh의 함수 시그니처(이름, 파라미터 개수)를 변경하지 마라.** 기존 statusline.sh에서 호출하는 방식이 그대로 동작해야 한다.
8. **캐시 파일 경로 변경(P0-4)은 producer(fetch-plan-usage.sh)와 consumer(statusline.sh)와 installer(install.sh)를 동일 커밋에서 변경하라.** 불일치 시 캐시를 읽지 못한다.
9. **`format_tokens`, `format_time`, `make_bar`에 비숫자 입력이 들어오면 기본값(0, "0s", 빈 바)을 반환하라.** 에러로 종료하지 마라.
10. **LICENSE 파일 생성 전에 사용자에게 확인을 받아라.**

---

## 6. 의사결정 (Decisions)

### D1: 캐시 파일 위치

- **채택:** `$HOME/.claude/plan-usage-cache.json` -- 사용자 전용 디렉토리, /tmp 심링크 공격 차단.
- **기각:** `/tmp/claude-plan-usage.json` -- 다중 사용자 환경에서 심링크 공격으로 임의 파일 덮어쓰기 가능 (P0-4).

### D2: 함수 추출 방식

- **채택:** `lib/hud-utils.sh` 별도 파일 + `source` -- 테스트에서 직접 source하여 단위 테스트 가능. statusline.sh 복잡도 감소.
- **기각:** statusline.sh 내 함수 유지 + source-guard만 추가 -- 테스트 시 stdin 블로킹 회피가 복잡하고, 함수와 메인 로직이 뒤섞인다.

### D3: 테스트 프레임워크

- **채택:** BATS (bats-core + bats-assert + bats-support) -- bash 네이티브, TAP 출력, CI 통합 용이, 커뮤니티 활성.
- **기각:** shunit2 -- BATS 대비 assertion 매크로 빈약, 파일당 setup/teardown 패턴 불편.
- **기각:** plain bash (test scripts) -- assertion 라이브러리 부재, 실패 진단 어려움.

### D4: CI 도구

- **채택:** GitHub Actions -- 프로젝트가 GitHub에 호스팅됨, 무료 tier 충분, shellcheck + bats 단일 job으로 구성.
- **기각:** CI 없음 -- 테스트/린트를 수동 실행에 의존하면 회귀 방지 불가.

### D5: curl 에러 처리

- **채택:** `curl -sS --fail` + `2>&1`로 stderr 캡처 + curl exit code 검사 -- TLS/HTTP 에러를 캐시 파일 error 필드에 기록하여 디버깅 가능.
- **기각:** `curl -s 2>/dev/null`(현재 방식) -- TLS 인증서 오류, 네트워크 장애가 완전히 무시됨.
- **기각:** HTTP 상태 코드 수동 검사 (`-o` + `-w '%{http_code}'`) -- `--fail`이 4xx/5xx에서 non-zero exit를 반환하므로 별도 파싱 불필요.

### D6: source 경로 해석 (statusline.sh -> lib/hud-utils.sh)

- **채택:** `_hud_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"` -- POSIX 호환, symlink 환경에서 안정적.
- **기각:** `readlink -f "${BASH_SOURCE[0]}"` -- macOS에서 GNU readlink 없으면 실패.

### D7: BATS 설치 방식

- **채택:** git submodule -- 별도 패키지 매니저 불필요, CI에서 `checkout@v4 --submodules recursive`로 해결.
- **기각:** brew/apt로 시스템 설치 -- 개발자 환경마다 다르고 버전 고정 어려움.
