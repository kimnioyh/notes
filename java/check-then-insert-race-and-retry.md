# check-then-insert 레이스 컨디션과 유니크 제약 재시도

**한 문장**: 앱이 INSERT 전에 유니크 값(이벤트 `code`)을 "있나 확인 → 없으면 저장"하면 그 사이 동시 요청이 같은 값을 저장할 수 있으므로(TOCTOU), **DB UNIQUE 제약을 최종 방어선으로 두고 충돌 시 새 값으로 재시도**해야 한다. 반대로 **PK를 DB가 채번하는 INSERT는 이 문제가 없다.**

## 왜 헷갈렸나
- `existsByCode`로 미리 중복을 걸렀으니 안전하다고 생각했다. 하지만 "확인"과 "저장"이 별개 시점이라, 두 요청이 동시에 "없음"을 보고 둘 다 저장할 수 있다.
- "피드백 100명이 동시에 제출하면 터지나?"가 헷갈렸다 — 코드 채번과 같은 문제인 줄 알았는데, **PK를 DB가 만드는 INSERT는 완전히 다른(안전한) 경우**였다.

## 핵심

### 1. check-then-insert = TOCTOU 레이스
```
요청A: existsByCode("ABC") → 없음
요청B: existsByCode("ABC") → 없음   (거의 동시)
요청A: INSERT "ABC" → 성공
요청B: INSERT "ABC" → UNIQUE 위반 💥
```
"검사(Time Of Check)"와 "사용(Time Of Use)" 사이에 상태가 바뀌는 고전적 레이스. 사전 검사는 **레이스를 줄이지도 못하고** 쿼리만 늘린다(최종 판정은 어차피 DB 제약).

### 2. 해결: DB UNIQUE를 방어선으로, 충돌 시 재시도
사전 검사를 없애고, **일단 저장을 시도**한 뒤 유니크 위반이 나면 새 코드로 다시 시도한다.
- `Event.code`에 `@Column(unique = true)` → DB가 최종 심판.
- 저장 실패는 Spring에서 `DataIntegrityViolationException`(unchecked)으로 올라온다.
- `62^8`(≈2×10¹⁴) 공간이라 충돌은 사실상 없고, 몇 회 재시도면 충분.

### 3. 재시도는 "그 유니크 충돌"로만 한정
`DataIntegrityViolationException`은 **FK 위반·not-null 위반 등도** 포함한다. 무작정 다 재시도하면, 코드와 무관한 진짜 오류를 N번 헛시도하고 원인을 `INTERNAL_ERROR`로 덮어버린다.
→ 실패한 그 `code`가 **이미 존재하면** 유니크 충돌로 보고 재시도, 아니면 **즉시 rethrow**(DB 종류에 안 묶이는 판별법. 제약 이름 매칭보다 안전).

### 4. 트랜잭션 경계 주의
`@Transactional` 안에서 제약 위반이 나면 그 트랜잭션은 **rollback-only로 오염**돼, 같은 트랜잭션에서 재시도(재저장)가 안 된다.
→ 재시도하려면 **각 저장 시도가 독립 트랜잭션**이어야 한다. 서비스 메서드에 `@Transactional`을 붙이지 않으면 `saveAndFlush` 하나하나가 리포지토리 단독 트랜잭션으로 커밋/롤백되어, 한 번 실패해도 다음 시도가 깨끗한 상태에서 돈다. (`save`가 아니라 `saveAndFlush`로 INSERT를 **그 자리에서** 터뜨려야 catch가 잡는다.)

### 5. 반대: DB가 PK를 채번하는 INSERT는 안전
피드백 제출처럼 **앱이 유니크 값을 안 고르고** PK를 `@GeneratedValue(IDENTITY)`로 **DB가 부여**하는 INSERT는 check-then-insert가 아예 없다. 100개 동시 INSERT여도 DB가 각각 유일한 id를 발급 → 앱 레벨 레이스 없음. (동시성 걱정은 대신 레이트리밋 카운터·상태 체크 같은 "읽고→쓰는" 다른 지점에서 봐야 함.)

## 예시 코드
Pulse `EventService.create` — 사전검사 제거 + 충돌 한정 재시도:

```java
// @Transactional 없음: 각 saveAndFlush가 독립 트랜잭션이어야 실패 후 재시도가 가능
public EventResponse create(Long ownerId, EventCreateRequest req) {
    User owner = userRepository.getReferenceById(ownerId);
    for (int attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt++) {
        String code = randomCode(); // SecureRandom base62 8자
        try {
            Event event = new Event(code, req.title(), req.description(), owner);
            eventRepository.saveAndFlush(event); // INSERT 즉시 실행 → 여기서 UNIQUE 위반이 잡힘
            return EventResponse.from(event);
        } catch (DataIntegrityViolationException e) {
            // 그 code가 이미 있으면 유니크 충돌 → 새 코드로 재시도.
            // 아니면(FK·not-null 등) 재시도해도 같은 실패이므로 즉시 전파해 원인을 감추지 않는다.
            if (!eventRepository.existsByCode(code)) throw e;
        }
    }
    throw new ApiException(ErrorCode.INTERNAL_ERROR); // 62^8에서 연속 충돌은 비정상
}
```

대조군 — `AuthService.signUp`도 같은 결의 패턴(이메일 UNIQUE): 사전 `findByEmail` 검사 + `save`의 `DataIntegrityViolationException`을 `EMAIL_ALREADY_EXISTS`로 매핑해 **동시 가입 레이스**를 방어한다.

## 확인 문제
1. `existsByCode`로 미리 확인하고 저장하는데도 왜 동시 요청에서 중복이 생길 수 있나? 근본 해결은?
2. `catch (DataIntegrityViolationException e)`를 그냥 두면 안 되는 이유는? 어떻게 "code 충돌"로만 한정하나?
3. 피드백 100명 동시 제출은 왜 이 레이스가 없나?

<details><summary>답</summary>

1. "확인"과 "저장"이 서로 다른 시점이라(TOCTOU), 두 요청이 동시에 "없음"을 보고 둘 다 저장할 수 있다. 사전 검사는 레이스를 못 막는다. 근본 해결은 **DB UNIQUE 제약을 최종 방어선으로 두고, 저장이 유니크 위반으로 실패하면 새 코드로 재시도**하는 것.

2. 그 예외는 FK·not-null 등 다른 무결성 위반도 포함해서, 코드와 무관한 진짜 오류를 5번 헛시도한 뒤 `INTERNAL_ERROR`로 덮어버린다. 실패한 `code`가 `existsByCode`로 **이미 존재하면** 유니크 충돌로 보고 재시도, 아니면 즉시 rethrow해서 한정한다(제약 이름 매칭보다 DB 독립적).

3. 피드백은 앱이 유니크 값을 고르지 않고 PK를 `@GeneratedValue(IDENTITY)`로 **DB가 채번**한다. 그래서 check-then-insert 자체가 없고, 동시 INSERT여도 DB가 각각 유일한 id를 발급한다. 레이스는 "앱이 유니크 값을 골라 넣는" 곳에서만 생긴다.

</details>

## 더 볼 것
- [[datajpatest-transaction-and-persistence-context]] — 트랜잭션 경계·rollback-only가 왜 재시도를 막는지
- 낙관적 락(@Version) — "같은 행을 동시에 수정"하는 다른 종류의 동시성 문제
