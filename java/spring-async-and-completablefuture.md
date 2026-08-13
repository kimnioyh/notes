# Spring 비동기 — @Async·@TransactionalEventListener·CompletableFuture

**한 문장**: Spring에서 백그라운드 작업은 `@Async`로 별 스레드에서 돌리되, **커밋 후 실행·self-invocation·실패 트랜잭션**을 챙겨야 하고, 결과를 받아 조합하려면 `CompletableFuture`(≈ JS Promise), 던져놓고 잊으면 `@Async void`를 쓴다.

## 왜 헷갈렸나
리포트 채우기를 비동기로 하려는데 (1) 언제 실행돼야 GENERATING 행을 볼 수 있는지, (2) `@Async`를 같은 클래스에서 부르면 왜 안 먹는지, (3) 실패 시 왜 상태가 저장이 안 되는지, (4) `CompletableFuture`가 꼭 필요한지가 안 잡혔다.

## 핵심

### 1. @Async = 메서드를 별 스레드에서 실행
- `@EnableAsync`(설정 클래스)가 있어야 동작. 없으면 그냥 동기.
- 반환 타입으로 용도가 갈린다:
  | 반환 | 언제 |
  |---|---|
  | `void` | 결과 안 받는 fire-and-forget |
  | `CompletableFuture<T>` | 호출자가 결과를 받아 조합·후속 처리할 때 |

### 2. 커밋 후 실행 = @TransactionalEventListener(AFTER_COMMIT)
비동기 워커가 "방금 저장한 행"을 조회하려면, 그 행이 **커밋돼 다른 트랜잭션에서도 보여야** 한다. 그냥 `@Async`로 바로 부르면 원 트랜잭션 커밋 전에 워커가 돌아 행을 못 볼 수 있다.
→ 원 서비스가 저장 후 **도메인 이벤트를 발행**하고, 워커는 `@TransactionalEventListener(phase = AFTER_COMMIT)`로 **커밋된 뒤** 받는다. 여기에 `@Async`를 얹으면 커밋 후 + 별 스레드.

### 3. self-invocation 함정 → 별도 빈
`@Async`·`@Transactional`은 **프록시를 거쳐야** 적용된다. 같은 클래스 안에서 자기 메서드를 부르면 프록시를 안 거쳐 무시된다([[spring-transactional-self-invocation]]). 그래서 실제 채우기 로직은 **다른 빈**(예: `ReportFiller`)에 두고 워커가 그 빈을 주입받아 호출한다.

### 4. 실패 트랜잭션 함정 → REQUIRES_NEW로 분리
작업 중 예외가 JPA/JDBC에서 나면 그 트랜잭션은 **rollback-only**로 마킹된다. 그 상태에서 "상태를 FAILED로 저장"을 같은 트랜잭션에 얹으면 커밋 자체가 실패해 **저장이 안 되고 GENERATING에 갇힌다**.
→ 성공 채우기(`fill`)와 실패 표시(`markFailed`)를 나누고, `markFailed`는 `@Transactional(propagation = REQUIRES_NEW)`로 **독립 트랜잭션**에서 저장한다. 그리고 `@Async`라 예외가 호출자에게 안 가므로 **직접 로깅**해야 원인이 남는다.

### 5. CompletableFuture ≈ JS Promise (필요할 때만)
비동기 "결과를 받아 조합"할 때 쓴다. Promise를 써봤으면 API가 거의 1:1로 대응:
| JS Promise | CompletableFuture |
|---|---|
| `.then` (변환) | `.thenApply` |
| `.then`(플랫맵) | `.thenCompose` |
| `.catch` | `.exceptionally`/`.handle` |
| `Promise.all` | `CompletableFuture.allOf` |
| `Promise.race` | `anyOf` |
- **근본 차이**: JS Promise는 단일 스레드 이벤트 루프(동시성 흉내), CompletableFuture는 **실제 멀티스레드**(`ForkJoinPool` 또는 지정 Executor).
- 우리는 채우기 결과를 **호출자가 받지 않는다**(202 후 폴링). 그래서 `@Async void`로 충분하고 CompletableFuture는 불필요(YAGNI). 나중에 LLM 여러 호출을 `allOf`로 병렬 조합하면 그때 등장한다.

## 예시 코드
Pulse 리포트 비동기 생성:
```java
// 원 서비스: 저장 후 이벤트 발행(@Transactional 안), 202 반환
reportRepository.save(report);                    // GENERATING
eventPublisher.publishEvent(new ReportGenerationRequested(report.getId(), eventCode));

// 워커: 커밋 후 별 스레드. 성공/실패를 각각 독립 트랜잭션(별 빈 ReportFiller)에 위임.
@Async
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
public void onReportRequested(ReportGenerationRequested e) {
    try { filler.fill(e.reportId(), e.eventCode()); }        // @Transactional
    catch (RuntimeException ex) {
        log.error("리포트 생성 실패 reportId={}", e.reportId(), ex);
        filler.markFailed(e.reportId());                     // @Transactional(REQUIRES_NEW)
    }
}
```

## 확인 문제
1. 리포트 채우기를 `generate` 안에서 바로 안 하고 `@TransactionalEventListener(AFTER_COMMIT)` + 별도 빈으로 뺀 이유 두 가지는?
2. 실패 표시(`markFailed`)를 왜 `REQUIRES_NEW`로 별도 트랜잭션에 두나? 안 그러면?
3. `@Async void`와 `@Async CompletableFuture<T>`는 언제 각각 쓰나?

<details><summary>답</summary>

1. (a) 워커가 GENERATING 행을 조회하려면 원 트랜잭션이 커밋된 뒤여야 하므로 `AFTER_COMMIT`이 필요하다. (b) `@Async`·`@Transactional`은 프록시를 거쳐야 적용되는데 같은 클래스 자기호출은 프록시를 건너뛰어 무시되므로, 실제 로직을 별도 빈에 둬야 비동기·트랜잭션이 실제로 먹는다.

2. 작업 트랜잭션이 예외로 rollback-only가 되면 그 위에 얹은 FAILED 저장도 커밋이 실패해 상태가 안 남고 GENERATING에 갇힌다. `REQUIRES_NEW`로 독립 트랜잭션에서 저장해야 실패 트랜잭션과 무관하게 FAILED가 확정된다.

3. 결과를 호출자가 받지 않는 fire-and-forget이면 `void`, 결과를 받아 후속 처리·조합(`allOf` 등)해야 하면 `CompletableFuture<T>`.

</details>

## 더 볼 것
- [[spring-transactional-self-invocation]] — 별도 빈으로 뺀 근본 이유
- [[async-202-polling]] — 이 워커가 채우는 동안 클라는 어떻게 완료를 아나
- [[datajpatest-transaction-and-persistence-context]] — 테스트에선 @Async가 안 도는 슬라이스라 워커를 동기로 호출해 검증
