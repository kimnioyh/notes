# ddl-auto=update와 enum CHECK 제약 드리프트

**한 문장**: `ddl-auto=update`는 컬럼·테이블은 추가해도 **기존 CHECK 제약은 갱신하지 않아서**, enum 값을 추가하면 배포 DB(Postgres)의 낡은 제약이 새 값을 거부한다.

## 왜 헷갈렸나
로컬에선 멀쩡히 되던 세션 생성이 배포(Neon)에서만 이 에러로 터졌다:
```
org.postgresql.util.PSQLException: ERROR: new row for relation "sessions"
violates check constraint "sessions_status_check"
```
코드는 그대로인데 왜 배포에서만? "제약 이름은 또 어디서 나온 거지?" 싶었다.

## 핵심
- `@Enumerated(EnumType.STRING)` 컬럼은 Hibernate가 스키마 생성 시 **CHECK 제약을 자동으로 만든다**: `<table>_<column>_check`, 내용은 `status IN ('현재','enum','값들')`.
- 이 제약은 **테이블이 처음 만들어진 시점의 enum 값**으로 고정된다.
- `spring.jpa.hibernate.ddl-auto=update`는 스키마를 **비파괴적으로 확장**만 한다 — 컬럼 추가는 하지만 **이미 존재하는 CHECK 제약은 손대지 않는다.**
- 그래서 enum에 값을 추가하면(예: `SessionStatus`에 `CLOSED` 추가), 배포 DB의 제약은 옛날 `{ACTIVE, DELETED}`인 채라 `CLOSED`를 거부한다.
- **로컬은 왜 통과?** 로컬은 `create-drop`(또는 `create`)이라 매 실행마다 스키마를 새로 구워 제약이 항상 최신. → 로컬↔배포 parity 갭. (H2를 `MODE=PostgreSQL`로 돌려도 이건 못 잡는다. ddl 전략 차이라서.)

## 예시 코드
enum이 이렇게 자랐을 때:
```java
// 최초
public enum SessionStatus { ACTIVE, DELETED }
// 나중에 CLOSED 추가 (지금은 세션 생성 기본값)
public enum SessionStatus { ACTIVE, CLOSED, DELETED }
```
배포 DB(Neon)에서 낡은 제약을 직접 재생성해야 한다 (재배포로는 안 고쳐짐):
```sql
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_status_check;
ALTER TABLE sessions ADD  CONSTRAINT sessions_status_check
    CHECK (status IN ('ACTIVE','CLOSED','DELETED'));
```
현재 제약을 확인하려면:
```sql
SELECT conrelid::regclass AS tbl, conname, pg_get_constraintdef(oid)
FROM pg_constraint WHERE contype='c';
```

## 확인 문제
1. 로컬에선 안 터지고 배포에서만 터진 결정적 이유는?
2. `ddl-auto`를 `create`로 바꾸면 이 문제가 해결될까? 왜 그러면 안 될까?

<details><summary>답</summary>

1. ddl 전략이 다르기 때문. 로컬은 `create-drop`이라 매번 스키마를 새로 구워 CHECK 제약이 항상 현재 enum과 일치한다. 배포는 `update`라 기존 제약을 안 고쳐서 낡은 채로 남는다.
2. `create`는 부팅 시 **스키마를 통째로 드롭·재생성**한다 → 제약은 최신이 되지만 **운영 데이터가 전부 날아간다.** 그래서 배포엔 절대 금지. 올바른 해법은 CHECK 제약을 수동 `ALTER`로 고치거나, 근본적으론 Flyway/Liquibase 같은 마이그레이션 도구로 스키마를 버전 관리하는 것.

</details>

## 더 볼 것
- Flyway/Liquibase — enum·제약 변경을 버전드 마이그레이션으로 관리하는 정석
- `ddl-auto` 값: `none` / `validate` / `update` / `create` / `create-drop`의 차이
