# Claude Code — 훅(hook) vs 스킬(skill)

**한 문장**: 훅은 "정해진 이벤트에 자동 실행되는 셸 명령"(판단 없음), 스킬은 "사용자가 부르면 Claude가 맥락을 읽고 수행하는 절차"(판단 있음)다.

## 왜 헷갈렸나

노트 캡처 도구를 "스킬로 만들었나, 훅으로 만들었나" 헷갈렸다. 둘 다 `~/.claude/` 아래 살고, 자동화 도구처럼 보여서 경계가 안 잡혔다. 핵심 기준은 **"Claude의 판단이 필요한가?"** 하나다.

## 핵심

### 결정 기준
- **개념을 이해해서 마크다운으로 정리** 같은 일 → Claude가 해야 함 → **스킬**.
- **"정해진 명령을 정해진 순간에 그냥 실행"**(로그 남기기, 알림, 리마인드 한 줄) → **훅**.
- 훅은 셸 명령일 뿐 Claude를 부르지 않는다. 그래서 "이해/작성"은 훅으로 못 한다.

| | 훅(hook) | 스킬(skill) |
|---|---|---|
| 발화 | 특정 이벤트에 **자동** | 사용자가 `/name` 호출 |
| 실행 주체 | 셸 명령 (Claude X) | Claude가 맥락 읽고 수행 |
| 할 수 있는 일 | 결정적 작업(로그·알림·차단) | 판단 필요한 작업(작성·분석·정리) |
| 정의 위치 | `settings.json`의 `hooks` | `~/.claude/skills/<name>/SKILL.md` |
| 배포 | 스크립트 + settings 등록 | 스킬 폴더 복사 |

### 조합해서 쓴다
훅으로 **넛지**, 스킬로 **실제 작업**. 예: `SessionEnd` 훅이 "정리해 두자" 한 줄만 출력 → 사용자가 `/note` 스킬을 호출해 Claude가 노트를 씀. 무거운 로직은 전부 스킬에, 훅은 경로/환경에 안 묶인 가벼운 트리거로.

### 훅 이벤트 종류 (언제 발화하나)
- **`UserPromptSubmit`** — 사용자가 프롬프트를 보낼 때마다. 입력 가공/키워드 감지에 쓰지만 오탐 많음.
- **`Stop`** — Claude가 응답을 끝낼 때마다. 매 턴이라 자주 발화 → 리마인드용으론 시끄러움.
- **`SessionEnd`** — 세션이 끝날 때 한 번. 회고·정리 넛지에 타이밍이 맞고 조용함.
- 훅 하나의 이벤트에 command를 배열로 여러 개 등록할 수 있다(기존 것에 이어 붙이면 됨).

**넛지엔 왜 `SessionEnd`인가**: "오늘 배운 것 정리해"는 세션이 끝나는 순간이 자연스럽다. `Stop`은 매 응답마다라 과함, `UserPromptSubmit`은 입력마다라 더 과함.

## 예시 코드

`settings.json`에 SessionEnd 훅 등록 (배열에 이어 붙이기):

```json
"SessionEnd": [
  {
    "hooks": [
      { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/brigh/.claude/session-log.ps1\"" },
      { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/brigh/.claude/note-reminder.ps1\"" }
    ]
  }
]
```

훅 스크립트(`note-reminder.ps1`)는 판단 없이 한 줄만:

```powershell
Write-Host "[note] 오늘 새로 이해한 개념 있었으면 /note 로 정리해 두자."
```

스킬(`SKILL.md`)은 프론트매터 + 절차를 Claude에게 지시:

```markdown
---
name: note
description: ... "/note" 같은 요청에 사용.
---
프로젝트 세션에서 배운 개념을 마크다운 노트로 정리해 ...
## 1. 정리할 개념 확보
## 2. 카테고리 결정
## 3. 노트 작성
## 4. 게시
```

→ 훅은 `settings.json` + 스크립트, 스킬은 폴더 하나. 이 노트를 만든 `/note`가 정확히 이 조합(SessionEnd 넛지 훅 + note 스킬)이다.

## 더 볼 것
- 스킬 배포: 스킬 폴더 복사 + `note.config.json` 설정 파일로 환경 의존 값 분리
- `frontmatter`의 `description`이 스킬 자동 발화 트리거를 결정한다(키워드를 잘 적을 것)
