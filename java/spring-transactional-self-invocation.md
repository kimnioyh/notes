# Spring @Transactional — self-invocation과 private 함정

**한 문장**: `@Transactional`은 Spring이 만든 **프록시가 메서드 호출을 가로채** 트랜잭션을 여는 것이라, 같은 클래스 안에서의 자기호출(self-invocation)이나 `private` 메서드에는 프록시를 안 거쳐 **어노테이션이 조용히 무시**된다.

## 왜 헷갈렸나
게이트 로직을 `private @Transactional`로 뽑았는데, "이 메서드가 트랜잭션을 여는 건가?"가 안 잡혔다. 실제로는 그 `@Transactional`은 무시되고, **호출자(`submit`)의 `@Transactional`이 연 트랜잭션 안에서** 도는 거라 LAZY 로딩이 되는 것이었다.

## 핵심

### 1. @Transactional = 프록시가 감싸서 여닫는다
Spring은 `@Transactional`이 붙은 빈을 **프록시 객체**로 감싼다. 외부에서 그 빈의 메서드를 부르면 프록시가 먼저 트랜잭션을 열고 → 실제 메서드 실행 → 커밋/롤백한다.
```
[호출자] → [프록시: tx 시작] → [실제 빈 메서드] → [프록시: commit]
```

### 2. 그래서 두 경우엔 무시된다
- **self-invocation**: 같은 클래스 안에서 `this.other()`로 부르면 **프록시를 안 거치고** 실제 객체를 직접 호출 → `other()`의 `@Transactional`이 안 먹는다.
- **private**: 프록시는 오버라이드로 가로채는데 `private`은 오버라이드 대상이 아니라 아예 가로챌 수 없다.

### 3. 그런데도 동작하는 이유 = 호출자의 트랜잭션이 커버
`public @Transactional submit()`이 트랜잭션을 열면, 그 안에서 부른 `private loadSubmittableSession()`은 **같은 스레드·같은 트랜잭션** 안에서 실행된다. 트랜잭션은 스레드에 바인딩되므로, 안쪽 메서드에 `@Transactional`이 없어도(또는 무시돼도) LAZY 로딩·dirty checking이 다 된다.
→ 결론: 안쪽 `private` 메서드의 `@Transactional`은 **효과가 없고 오해만 부르니 제거**가 깔끔. 트랜잭션 경계는 진입점(public)에 둔다.

### 4. 정말 안쪽에서 별도 경계가 필요하면
자기호출로는 안 되니 (1) 그 메서드를 **다른 빈으로 분리**해 주입받아 호출하거나, (2) `AopContext.currentProxy()`로 프록시를 통해 부른다. 대부분은 진입점에 경계를 두면 충분해서 불필요.

### 5. @DataJpaTest에서 서비스를 `new`로 조립하면 전부 무시된다
테스트에서 `new FeedbackService(...)`로 직접 만들면 **프록시가 아니라** `@Transactional`이 전부 no-op이다. 대신 `@DataJpaTest`가 각 테스트를 감싸는 **테스트 트랜잭션**이 있어 그 안에서 LAZY 로딩·flush가 된다(그래서 테스트는 통과). → [[datajpatest-transaction-and-persistence-context]]

## 예시 코드
Pulse `FeedbackService`:
```java
@Transactional
public FeedbackView submit(String eventCode, FeedbackSubmitRequest req, String clientId) {
    Session session = loadSubmittableSession(eventCode, req.sessionId()); // 자기호출
    ...
}

// @Transactional 붙여도 무시됨(private + self-invocation). submit의 tx가 커버해 LAZY 접근 OK.
private Session loadSubmittableSession(String eventCode, Long sessionId) {
    Event event = eventRepository.findByCode(eventCode).orElseThrow(...);
    ...
    if (!session.getEvent().getId().equals(event.getId())) ...  // getEvent()=LAZY, tx 안이라 OK
}
```

## 확인 문제
1. `private @Transactional` 메서드의 어노테이션이 무시되는데도 그 안에서 LAZY 로딩이 되는 이유는?
2. 같은 클래스의 `public @Transactional` 메서드를 `this.method()`로 부르면 트랜잭션이 열릴까? 안 열린다면 왜?

<details><summary>답</summary>

1. 호출자(public `@Transactional`)가 이미 트랜잭션을 열었고, 트랜잭션은 스레드에 바인딩되므로 같은 스레드에서 부른 안쪽 메서드도 그 트랜잭션(영속성 컨텍스트) 안에서 실행된다. 그래서 안쪽 어노테이션이 무시돼도 LAZY 로딩이 된다.

2. 안 열린다. `this.method()`는 프록시를 거치지 않고 실제 객체를 직접 호출하기 때문이다. `@Transactional`은 프록시가 호출을 가로채야 작동하는데 self-invocation은 그 가로채기를 건너뛴다.

</details>

## 더 볼 것
- [[datajpatest-transaction-and-persistence-context]] — 테스트에서 프록시 없이도 tx가 도는 이유
- [[jpa-lazy-loading]] — 트랜잭션이 닫히면 LAZY가 터지는 배경
- [[spring-02-container-and-bean]] — 빈이 프록시로 감싸지는 컨테이너 맥락
