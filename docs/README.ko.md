# Claude Code HUD

Claude Code의 status line에 사용량 정보를 실시간으로 표시하는 커스텀 HUD.

[English](../README.md) | [日本語](README.ja.md) | [中文](README.zh.md)

## 미리보기

```
Opus 4.6 (1M context) | 5m 0s (api:3m 0s) | $1.23 | d:$4.56 m:$78.90 | in:45.2K out:12.8K
ctx  [███████░░░░░░░░░░░░░] 35%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| 줄 | 내용 |
|----|------|
| 1 | 모델명, 세션 시간(API 시간), 세션 비용, 일간/월간 누적 비용, 입출력 토큰 |
| 2 | 컨텍스트 윈도우 사용률 바 |
| 3 | 5시간 플랜 한도 사용률 + 리셋 타이머 |
| 4 | 주간 플랜 한도 사용률 + 리셋 타이머 |

- 바 색상: 초록(<50%) → 노랑(50-79%) → 빨강(80%+)
- 세션 비용: 현재 세션만 표시 (노랑)
- `d:` / `m:`: 과거 완료된 세션의 누적 비용 (일간 / 월간)

## 설치

### macOS / Linux

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

제거: `./install.sh --uninstall`

### Windows (PowerShell 7+)

```powershell
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud\win
.\install.ps1
```

제거: `.\install.ps1 -Uninstall`

두 설치 스크립트 모두 `~/.claude/settings.json`을 자동으로 설정한다. 설치 후 Claude Code 재시작 필요.

## 동작 방식

### Status Line (`statusline.sh`)

Claude Code가 stdin으로 보내는 세션 JSON을 읽어 대시보드를 렌더링:
- 세션 지표 (비용, 시간, 토큰)
- 컨텍스트 윈도우 사용률 바
- 플랜 사용률 바 + 리셋 타이머 (캐시된 API 데이터)
- 과거 세션의 일간/월간 누적 비용 (`usage-log.jsonl` 기반)
- 매 갱신마다 세션 스냅샷 저장 (SessionEnd 훅용)

### 플랜 사용량 (`fetch-plan-usage.sh`)

- `api.anthropic.com/api/oauth/usage` OAuth API 호출
- 토큰 소스: `~/.claude/.credentials.json` 또는 macOS Keychain
- 30초 캐시 (`~/.claude/plan-usage-cache.json`)로 status line 속도에 영향 없음
- 캐시가 stale하면 백그라운드에서 자동 갱신

### 세션 로깅 (`log-session.sh`)

- SessionEnd 훅으로 `statusline.sh`가 저장한 세션 스냅샷을 읽어 로그에 기록
- 비용/토큰/시간 지표를 `~/.claude/usage-log.jsonl`에 JSONL로 저장
- 모든 프로젝트의 사용량이 하나의 로그 파일에 글로벌로 누적

## 파일 구조

```
statusline.sh          # HUD 메인 스크립트 (stdin JSON 파싱, 출력 렌더링)
fetch-plan-usage.sh    # OAuth API 플랜 사용량 조회 + 백그라운드 캐시
log-session.sh         # SessionEnd 훅 - 세션 종료 시 비용을 JSONL로 기록
install.sh             # 설치/제거 스크립트 (macOS/Linux)
lib/hud-utils.sh       # 공유 유틸리티 함수 (statusline.sh에서 source)
win/                   # Windows PowerShell 포트 (statusline, fetch, log, install)
test/                  # BATS 테스트 스위트 (35개 테스트)
```

## 테스트

```bash
./test/bats/bin/bats test/*.bats
```

## 요구사항

- Claude Code (Max 플랜)
- macOS/Linux: `jq`, `curl`, `bc`
- Windows: PowerShell 7+ (`winget install Microsoft.PowerShell`)

## 라이선스

[MIT](../LICENSE)
