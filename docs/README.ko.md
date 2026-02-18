# Claude Code HUD

Claude Code의 status line에 사용량 정보를 실시간으로 표시하는 커스텀 HUD.

[English](../README.md) | [日本語](README.ja.md) | [中文](README.zh.md)

## 미리보기

```
Opus 4.6 | 13m 28s (api:8m 41s) | $2.07 | d:$2.07 m:$2.07 | in:88.9K out:26.7K
ctx  [█████░░░░░░░░░░░░░░░] 29%
5h   [░░░░░░░░░░░░░░░░░░░░]  4%  reset 3h 30m
week [████░░░░░░░░░░░░░░░░] 22%  reset 4d 19h
```

| 줄 | 내용 |
|----|------|
| 1 | 모델명, 세션 시간(API 시간), 세션 비용, 일간/월간 누적 비용, 입출력 토큰 |
| 2 | 컨텍스트 윈도우 사용률 바 |
| 3 | 5시간 플랜 한도 사용률 + 리셋 타이머 |
| 4 | 주간 플랜 한도 사용률 + 리셋 타이머 |

바 색상: 초록(<50%) → 노랑(50-79%) → 빨강(80%+)

## 설치

```bash
git clone https://github.com/kangnam7654/claude-code-hud.git
cd claude-code-hud
./install.sh
```

심볼릭 링크 생성 + `~/.claude/settings.json` 설정을 자동으로 처리한다. 설치 후 Claude Code를 재시작하면 적용됨.

제거:

```bash
./install.sh --uninstall
```

## 동작 방식

### Status Line (`statusline.sh`)

Claude Code가 stdin으로 보내는 세션 JSON을 읽어 다음을 표시:
- 세션 지표 (비용, 시간, 토큰)
- 컨텍스트 윈도우 사용률 바
- 플랜 사용률 바 + 리셋 타이머 (캐시된 API 데이터)
- 일간/월간 누적 비용 (세션 로그 기반)

### 플랜 사용량 (`fetch-plan-usage.sh`)

- `~/.claude/.credentials.json`의 OAuth 토큰으로 `api.anthropic.com/api/oauth/usage` 호출
- 30초 캐시 (`/tmp/claude-plan-usage.json`)로 status line 속도에 영향 없음
- 캐시가 stale하면 백그라운드에서 자동 갱신

### 세션 로깅 (`log-session.sh`)

- SessionEnd 훅으로 세션 종료 시 비용/토큰을 `~/.claude/usage-log.jsonl`에 기록
- statusline에서 현재 세션 비용 + 과거 세션 비용을 합산하여 표시

## 파일 구조

```
install.sh             # 설치/제거 스크립트
statusline.sh          # HUD 메인 스크립트 (status line에서 실행)
fetch-plan-usage.sh    # Anthropic OAuth API로 플랜 사용량 조회 + 캐시
log-session.sh         # SessionEnd 훅 - 세션 종료 시 비용을 JSONL로 기록
```

## 요구사항

- Claude Code (Max 플랜)
- `jq`, `curl`, `bc`
