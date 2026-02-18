# Claude Code HUD

## Project Overview

Claude Code의 status line에 사용량 정보를 표시하는 셸 스크립트 프로젝트.
서버/빌드 없이 순수 bash 스크립트로만 구성됨.

## Architecture

```
statusline.sh        ← Claude Code가 stdin으로 JSON을 보내면 파싱해서 HUD 출력
fetch-plan-usage.sh  ← OAuth API로 플랜 사용량 조회, /tmp에 30초 캐시
log-session.sh       ← SessionEnd 훅, ~/.claude/usage-log.jsonl에 세션 기록
install.sh           ← 심볼릭 링크 + settings.json 자동 설정
```

- 모든 스크립트는 `~/.claude/`에 심볼릭 링크로 설치됨
- `settings.json`의 `statusLine`과 `hooks.SessionEnd`로 Claude Code와 연결
- 플랜 사용량은 백그라운드 갱신 + 캐시로 status line 속도에 영향 없음

## Key Paths (runtime)

- `~/.claude/settings.json` — Claude Code 설정
- `~/.claude/.credentials.json` — OAuth 토큰 (플랜 사용량 API용)
- `~/.claude/usage-log.jsonl` — 세션별 비용 로그
- `/tmp/claude-plan-usage.json` — 플랜 사용량 캐시 (30초 TTL)

## Conventions

- 언어: Bash (POSIX 호환 지향, bashism 최소화)
- 외부 의존성: `jq`, `curl`, `bc`만 사용
- 색상: ANSI escape code 직접 사용 (tput 미사용)
- README: 영어가 기본, 번역은 `docs/README.{ko,ja,zh}.md`

## When Editing

- statusline.sh 수정 시 실제 Claude Code에서 테스트 필요 (stdin으로 JSON 받음)
- install.sh 수정 시 `bash -n install.sh`로 문법 검증
- 새 스크립트 추가 시 install.sh의 `LINKS` 배열에도 추가할 것
