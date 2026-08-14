# check-then-insert 레이스와 saveAndFlush로 UNIQUE 위반 잡기

**한 문장**: "존재하나 확인 → 없으면 INSERT" 사이엔 동시성 레이스가 있어서, 사전 검사에만 의존하지 말고 **DB UNIQUE 제약을 최종 방어선**으로 두고 위반을 잡아 도메인 에러로 매핑한다.

## 왜 헷갈렸나
리포트 생성이 "이미 있나 조회 → 없으면 생성"인데, 동시에 두 번 들어오면 500이 났다. "조회로 막았는데 왜 중복이 생기지?" — 조회와 저장 **사이**에 다른 트랜잭션이 끼어들 수 있다는 걸 놓쳤다.

## 핵심
- **레이스**: 두 요청이 거의 동시에 오면, 둘 다 "아직 없음"을 읽고(둘 다 커밋 전) 둘 다 INSERT를 시도한다. 사전 조회(check)는 이 창을 못 막는다 (TOCTOU).
- **최종 방어선은 DB**: 컬럼에 `UNIQUE` 제약이 있으면 두 번째 INSERT가 DB에서 실패한다. 이걸 **잡아서** 사용자에겐 "이미 존재함(409)"로 매핑하면 500 대신 깔끔한 응답.
- **왜 `saveAndFlush`인가**: 그냥 `save`는 flush를 트랜잭션 커밋까지 미룰 수 있어, UNIQUE 위반이 메서드 밖(커밋 시점)에서 터져 `try/catch`로 못 잡는다. `saveAndFlush`는 **INSERT를 즉시 실행**해 위반을 그 자리(`try` 안)에서 잡게 한다. (IDENTITY 전략이면 `save`도 즉시 INSERT하지만, `saveAndFlush`로 의도를 명시.)
- **catch 범위**: `DataIntegrityViolationException`은 넓게 잡지만, 그 INSERT에서 실질적으로 가능한 제약이 해당 UNIQUE 하나뿐이면 오분류 위험이 없다.
- 트랜잭션 주의: 위반 후 예외를 던지면 트랜잭션이 롤백돼 실패한 INSERT가 정리된다. flush 실패한 `EntityManager`를 재사용하지 말 것.

## 예시 코드
```java
Report report = reportRepository.findByEvent_Code(code).orElse(null);
if (report == null) {
    report = new Report(event, ...);          // 신규
} else if (report.getStatus() != FAILED) {
    throw new ApiException(REPORT_ALREADY_EXISTS);  // 순차 중복은 여기서
}
try {
    reportRepository.saveAndFlush(report);     // INSERT 즉시 → UNIQUE 위반을 여기서 잡음
} catch (DataIntegrityViolationException e) {
    // 동시 요청 레이스: 다른 트랜잭션이 먼저 만들어 event_id UNIQUE 위반
    throw new ApiException(REPORT_ALREADY_EXISTS);  // 500 대신 409
}
```
같은 패턴을 회원가입 이메일 중복에도 씀(사전 `findByEmail` + `save` catch).

## 확인 문제
1. 사전 조회(`findBy...`)로 중복을 막는데도 왜 DB UNIQUE 제약과 catch가 또 필요한가?
2. `save` 대신 `saveAndFlush`를 쓰는 이유는?

<details><summary>답</summary>

1. 사전 조회는 "확인 시점"의 스냅샷일 뿐, 조회와 저장 **사이**에 다른 트랜잭션이 같은 값을 넣을 수 있다(check-then-act 레이스). 이 창은 애플리케이션 코드로 못 막고, 원자적 보장은 DB UNIQUE 제약만 할 수 있다. 그래서 조회는 흔한 경우를 빨리 걸러주고(사용자 친화적 메시지), UNIQUE+catch가 레이스의 최종 방어선이 된다.
2. `save`는 flush를 커밋까지 미룰 수 있어 UNIQUE 위반이 `try` 블록 **밖**에서 터진다 → catch 못 함 → 500. `saveAndFlush`는 INSERT를 즉시 실행해 위반을 `try` 안에서 잡아 409로 매핑할 수 있다.

</details>

## 더 볼 것
- TOCTOU (Time-of-check to time-of-use) 레이스
- 낙관적 락 `@Version` — UPDATE 경로의 동시성(INSERT UNIQUE로는 못 잡는 케이스)
