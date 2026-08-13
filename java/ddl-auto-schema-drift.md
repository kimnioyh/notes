# ddl-auto=update의 한계와 배포 스키마 드리프트

**한 문장**: `spring.jpa.hibernate.ddl-auto=update`는 **컬럼·테이블 추가**만 하고 **기존 컬럼의 타입 변경이나 삭제 같은 파괴적 변경은 하지 않아서**, 로컬(H2 `create-drop`)은 매번 새로 구워 통과하지만 기존 스키마를 유지하는 배포 DB(Neon 등)와 어긋나 배포에서만 터진다.

## 왜 헷갈렸나
Report 엔티티를 `String`(text) → JSON(jsonb) 컬럼으로 바꿨는데 **로컬 테스트는 다 통과**했다. 그런데 배포하니 `PSQLException: column "sentiment_breakdown" cannot be cast automatically to type jsonb`로 부팅이 실패했다. "로컬에서 됐는데 왜 배포에서만?"이 안 잡혔다.

## 핵심

### 1. ddl-auto 모드
| 값 | 동작 |
|---|---|
| `create-drop` | 시작 시 스키마 생성, 종료 시 삭제. **로컬 H2가 이걸 씀** → 매 실행 새 스키마 |
| `update` | 기존 스키마에 **없는 것만 추가**(컬럼/테이블). 파괴적 변경 안 함 |
| `validate` | 엔티티와 스키마 일치만 검사, 변경 안 함 |
| `none` | 아무것도 안 함(Flyway 등이 관리) |

### 2. update가 "안 하는" 것 = 드리프트의 원인
`update`는 **비파괴적**으로만 동작한다:
- 새 컬럼/테이블 **추가** ✅
- 기존 컬럼 **타입 변경**(text→jsonb) ❌ — 데이터 손실 위험이라 안 함
- 컬럼/테이블 **삭제** ❌
- `@ElementCollection`(별도 테이블) ↔ 단일 컬럼 **전환** ❌

그래서 엔티티 타입을 바꾸면, 배포 DB엔 **옛 컬럼(text)이 그대로 남고** Hibernate가 그걸 jsonb로 못 바꿔 부팅이 깨진다.

### 3. 왜 로컬만 통과했나
- 로컬 H2 = `create-drop` → 매 실행 스키마를 **처음부터** 새로 구움 → 항상 새 엔티티 기준이라 충돌 없음.
- 배포 Neon = 기존 스키마 **유지** → 옛 컬럼이 남아 새 엔티티와 충돌.
→ "로컬 통과 ≠ 배포 안전". 스키마 변경은 배포 DB 관점으로 봐야 한다.

### 4. 해결
- **데이터가 없으면(개발 초기)**: 옛 테이블을 drop하고 재배포 → `update`가 새 스키마로 다시 생성. 가장 간단.
  ```sql
  DROP TABLE IF EXISTS reports;   -- 옛 컬럼 포함 통째로
  ```
- **실데이터가 있으면**: drop 불가. `ALTER ... USING`으로 명시 변환하거나
  ```sql
  ALTER TABLE reports ALTER COLUMN sentiment_breakdown TYPE jsonb USING sentiment_breakdown::jsonb;
  ```
- **근본**: 스키마가 안정되면 **Flyway/Liquibase**로 변경을 버전 관리된 SQL로 명시. `ddl-auto=none`(또는 validate)로 두고 마이그레이션이 스키마를 책임진다.

## 예시 코드
Pulse Report: `sentiment_breakdown`을 text→jsonb, `topKeywords`를 `@ElementCollection`(report_top_keywords 테이블)→jsonb 컬럼으로 바꿨더니 배포에서 캐스트 에러. Neon엔 옛 `report`(단수 잔재)·`reports`(text)·`report_top_keywords`가 남아 있었다. 데이터가 0이라 옛 테이블을 drop하고 재배포해 `reports`가 jsonb 컬럼으로 새로 생성되게 해결.

## 확인 문제
1. 엔티티 타입을 바꿨는데 로컬 테스트는 통과하고 배포만 실패하는 이유는?
2. `ddl-auto=update`가 text→jsonb 타입 변경을 안 하는 이유와, 데이터가 있을 때/없을 때 각각의 해결책은?

<details><summary>답</summary>

1. 로컬 H2는 `create-drop`이라 매 실행 스키마를 처음부터 새로 구워 항상 새 엔티티 기준이지만, 배포 DB(Neon)는 기존 스키마를 유지해 옛 컬럼(text)이 남는다. `update`는 그 옛 컬럼을 jsonb로 못 바꿔 배포 부팅이 실패한다.

2. `update`는 데이터 손실 위험이 있는 파괴적 변경(타입 변경·삭제)을 일부러 안 한다. 데이터가 없으면 옛 테이블을 drop하고 재배포해 새로 생성하면 되고, 데이터가 있으면 `ALTER ... USING`으로 명시 변환하거나 Flyway 같은 마이그레이션 도구로 SQL을 버전 관리한다.

</details>

## 더 볼 것
- [[hibernate-json-column]] — text→jsonb로 바꾼 그 매핑
- [[datajpatest-transaction-and-persistence-context]] — 로컬 슬라이스 테스트가 배포 스키마를 대변하지 못하는 배경
