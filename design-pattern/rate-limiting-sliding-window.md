# 레이트리밋 — 인메모리 슬라이딩 윈도우

**한 문장**: "분당 N회"를 정확히 지키려면 매 요청마다 **"지금 기준 직전 60초"** 안의 요청 수를 세야 하고(슬라이딩 윈도우), 인메모리로는 `Map<key, Deque<Instant>>`에 요청 시각을 기록해 오래된 건 앞에서 버리고 개수를 확인한다.

## 왜 헷갈렸나
"카운터 하나 두고 3 넘으면 막자"가 먼저 떠올랐는데, **언제 0으로 리셋하냐**가 안 잡혔다. 매 분 리셋(고정 윈도우)은 경계에서 뚫린다. 그리고 "왜 세션당 1회로 안 막고 분당 3회를 허용하지?"도 헷갈렸는데, 그건 [[client-vs-server-enforcement]] 문제(중복방지 UX ≠ 레이트리밋)라 별개다.

## 핵심

### 1. 고정 윈도우의 구멍 = 경계 버스트
매 분 카운터를 리셋하면:
```
12:00:59  3개 제출  (12:00분 카운터 꽉 참)
12:01:00  리셋 → 또 3개    → 2초 만에 6개 통과
```
"분당 3회"라면서 짧은 순간 6회가 새어나간다.

### 2. 슬라이딩 윈도우 = 리셋 시점을 없애고 매번 "직전 60초"를 센다
요청 시각을 전부 기록해두고, 새 요청마다 `now - 60s`보다 오래된 기록은 버린 뒤 남은 개수를 본다. 창이 현재 시각을 따라 미끄러진다(slide).
```
12:00:10,:20,:30 통과 → 기록 [10,20,30]
12:00:40 → 직전 60초에 3개 → 거부(429)
12:01:15 → :10이 60초 밖으로 만료 → 남은 [20,30] 2개 → 통과
```

### 3. 자료구조: 왜 Deque이고 왜 Map
- **Deque**: 오래된 건 **앞에서** 버리고(`pollFirst`) 새 시각은 **뒤에** 붙인다(`addLast`). 시각이 시간순이라 맨 앞이 가장 오래됨.
- **Map**: 키(`sessionId:clientId`)마다 기록이 따로 있어야 서로 안 섞인다. `Map<String, Deque<Instant>>`.

### 4. 알고리즘 4단계
1. 키로 deque 꺼냄(없으면 생성) — `computeIfAbsent`
2. `now - WINDOW`보다 앞선 원소를 맨 앞에서 계속 제거
3. 남은 `size() >= LIMIT`이면 거부 (`>=`라 3개 있을 때 **4번째**가 컷 — 정확히 "분당 3회")
4. 통과면 `now`를 뒤에 추가

### 5. 동시성 — 여기가 진짜 함정
같은 키 두 요청이 `size 확인`을 동시에 통과(둘 다 2개로 봄)하면 둘 다 추가해 4개가 된다. 막으려면:
- **각 deque 조작(2~4단계)을 `synchronized (log)`로** 원자화. 같은 키만 직렬화되고 **다른 키는 병렬 유지**(Map 전체 락보다 빠름).
- **Map은 `ConcurrentHashMap`** — `computeIfAbsent`(키 삽입) 자체도 동시성 안전해야.
즉 두 겹: Map은 ConcurrentHashMap, deque는 synchronized.

### 6. 검증(게이트)을 레이트리밋보다 먼저
존재하지 않거나 CLOSED인 세션에도 레이트를 기록하면 (1) 실패할 요청이 정상 여유를 잡아먹고 (2) 공격자가 아무 sessionId나 던져 **쓰레기 키로 Map을 오염**시킨다. 그래서 순서는 **게이트 → 레이트리밋 → 저장** — "검증된 요청만 카운트".

### 7. 한계
- **단일 인스턴스 전제**. 서버 여러 대면 각자 세서 부정확 → 공유 저장소(Redis)로.
- **메모리 누수**: 안 쓰는 키의 빈 deque가 Map에 남는다. 학습 규모면 방치(`ponytail:` 주석)하고, 필요해지면 주기적 청소.
- **인메모리라 트랜잭션과 무관**: 저장이 롤백돼도 이미 기록한 시각은 안 돌아간다(레이트리밋은 근사치라 실무상 OK).

## 예시 코드
Pulse `FeedbackService` — 소감 제출(공개) 레이트리밋:
```java
private final Map<String, Deque<Instant>> rateLog = new ConcurrentHashMap<>();
private static final int LIMIT = 3;
private static final Duration WINDOW = Duration.ofMinutes(1);

private void checkRateLimit(Long sessionId, String clientId) {
    String key = sessionId + ":" + clientId;
    Deque<Instant> log = rateLog.computeIfAbsent(key, k -> new ArrayDeque<>());
    synchronized (log) {
        Instant cutoff = Instant.now().minus(WINDOW);
        while (!log.isEmpty() && log.peekFirst().isBefore(cutoff)) log.pollFirst();
        if (log.size() >= LIMIT) throw new ApiException(ErrorCode.RATE_LIMIT_EXCEEDED);
        log.addLast(Instant.now());
    }
}
```
키가 `(sessionId, clientId)`라 세션마다 따로 센다. `clientId`는 `X-Client-Id` 헤더(FE UUID), 없으면 IP 폴백 — 단 NAT 뒤 여러 사람이 같은 IP면 서로 카운트를 공유해 오탐(false positive)이 난다(트레이드오프).

## 확인 문제
1. 고정 윈도우 대신 슬라이딩을 쓰는 이유를 경계 버스트 예시로 설명해봐.
2. `synchronized`를 Map 전체가 아니라 개별 deque에 거는 게 왜 나은가? 아예 안 걸면 무슨 버그?
3. 조건이 `>=`가 아니라 `>`면 LIMIT=3에서 몇 개까지 통과하나? 계약과 왜 어긋나나?

<details><summary>답</summary>

1. 고정 윈도우는 12:00:59에 3개 + 리셋 직후 12:01:00에 3개 = 짧은 순간 6개가 통과(경계 버스트). 슬라이딩은 리셋 시점 없이 항상 "직전 60초"만 봐서 이 구멍이 없다.

2. 개별 deque 락은 같은 키만 직렬화하고 다른 키(다른 사용자)는 병렬로 통과시켜 빠르다. Map 전체 락은 무관한 사용자끼리도 줄 세운다. 안 걸면 같은 키 두 요청이 size 확인을 동시에 통과해 둘 다 addLast → 제한을 넘겨 저장된다.

3. `> 3`이면 4개까지 통과하고 5번째가 막혀 "분당 3회"가 아니라 사실상 4회가 된다. `>= 3`이라야 3개 있을 때 4번째가 컷되어 정확히 분당 3회.

</details>

## 더 볼 것
- [[client-vs-server-enforcement]] — "세션당 1회(FE)"와 "분당 3회(서버)"가 왜 별개인지
- [[spring-transactional-self-invocation]] — 왜 인메모리 레이트 기록은 트랜잭션 롤백과 무관한지의 배경
