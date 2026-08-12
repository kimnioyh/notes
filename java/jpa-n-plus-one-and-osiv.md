# N+1 쿼리와 OSIV (Open Session In View)

**한 문장**: N+1은 목록 1번 조회 뒤 각 항목의 LAZY 연관을 채우려 N번 더 쿼리가 나가는 문제이고, OSIV는 영속성 세션을 HTTP 요청 끝(직렬화 포함)까지 열어둬 `LazyInitializationException`은 막아주지만 그 대가로 N+1을 조용히 숨긴다.

## 왜 헷갈렸나
CodeRabbit이 "DTO에 LAZY 컬렉션(`keywords`)을 그대로 담으면 직렬화 중 `LazyInitializationException`이 난다"고 지적했는데, 실제로 테스트·로컬에선 **안 터졌다.** "그럼 왜 지적하지?"가 안 잡혔다. 답은 **OSIV가 기본으로 켜져 있어 가려주고 있었기 때문**이고, 그 대신 N+1이라는 다른 비용을 치르고 있었다.

## 핵심

### 1. N+1 = 1번 + N번
```
목록 조회 1번  → 소감 50개
각 소감의 keywords 로딩 → 50번 추가 SELECT
합계 = 1 + 50 = 51번
```
"하나 조회했더니 연관이 줄줄이 딸려나온다"라 이름이 **N+1**. LAZY 연관을 목록에서 항목마다 건드릴 때 전형적으로 발생한다.

### 2. OSIV = 세션을 언제까지 여느냐
`@ElementCollection`·`@OneToMany` 등은 LAZY라, 실제로 건드릴 때 세션(영속성 컨텍스트)이 살아 있어야 로딩된다. **OSIV는 그 세션을 서비스 트랜잭션이 아니라 HTTP 요청 끝까지 연장**한다.

| open-in-view | 세션 닫히는 시점 | DTO의 LAZY 컬렉션 직렬화 |
|---|---|---|
| **true (Spring Boot 기본)** | HTTP 응답 완료 | ✅ 됨 (직렬화까지 세션 열림) |
| **false** | 서비스 트랜잭션 끝 | ❌ `LazyInitializationException` |

- **true**: 편하지만 직렬화 중 LAZY 로딩이 일어나 **N+1이 컨트롤러/뷰 계층까지 숨어든다.** 논란이 있는 기본값(끄기를 권하는 시각도 많음).
- **false**: 트랜잭션 경계 밖에서 LAZY 접근하면 바로 터지므로, DTO를 **트랜잭션 안에서 완성**해야 한다는 규율이 강제된다.

### 3. 방어 두 가지
- **`List.copyOf(f.getKeywords())`** — DTO 만들 때 트랜잭션 안에서 컬렉션을 즉시 다 읽어 복사. 세션이 닫혀도 안전(더는 LAZY 아님). OSIV 여부와 무관해진다. (LazyInit는 막지만 N+1 자체는 남음)
- **fetch join / `@EntityGraph`** — 목록 쿼리에서 연관을 애초에 한 번에 가져와 N+1을 없앤다. 단 컬렉션 fetch join + `Pageable`은 메모리 페이징 경고가 있어 주의.

### 4. 언제 그냥 두나
저트래픽 관리자 화면(모더레이션 큐 등)에서 N+1 50번은 실사용에 문제가 안 된다. 무조건 없애기보다 **트래픽·목록 크기를 보고 판단**한다. 단 OSIV를 끄기로 하면 LazyInit 방어(`copyOf`/fetch join)는 필수가 된다.

## 예시 코드
Pulse `AdminFeedbackView.from` — LAZY `keywords`를 그대로 담는다:
```java
public static AdminFeedbackView from(Feedback f) {
    return new AdminFeedbackView(..., f.getKeywords(), ...); // OSIV=true라 현재는 동작(직렬화 시 로딩)
}
```
- 현재는 OSIV 기본값(true) 덕에 안 터지지만, 목록(`adminList`)이 커지면 항목마다 keywords SELECT가 나가는 N+1.
- `FeedbackView`·`EventResponse` 등 다른 뷰도 같은 패턴이라, 없애려면 **전체를 일괄로**(그래서 admin PR에선 수용하고 남겨둠).

## 확인 문제
1. N+1이 정확히 무슨 상황이고, 왜 "1 + N"이라 부르나?
2. LAZY 컬렉션을 DTO에 담았는데 로컬에선 `LazyInitializationException`이 안 난다. 왜일까? 그 편의의 숨은 비용은?

<details><summary>답</summary>

1. 목록을 1번 쿼리로 N개 가져온 뒤, 각 항목의 LAZY 연관을 채우려고 항목마다 1번씩(총 N번) 추가 쿼리가 나가는 것. 합쳐서 1 + N번이라 N+1. 지연 로딩된 연관을 목록에서 항목별로 건드릴 때 발생한다.

2. OSIV(open-in-view)가 기본 true라 영속성 세션이 HTTP 요청 끝(직렬화 포함)까지 열려 있어, DTO를 직렬화하는 시점에도 LAZY 로딩이 가능해 예외가 안 난다. 숨은 비용은 그 로딩이 목록 항목마다 일어나 N+1 쿼리가 컨트롤러/뷰 계층까지 스며드는 것. OSIV를 끄면 트랜잭션 밖 직렬화에서 바로 터지므로 `List.copyOf`나 fetch join으로 트랜잭션 안에서 DTO를 완성해야 한다.

</details>

## 더 볼 것
- [[jpa-lazy-loading]] — LAZY 프록시/컬렉션이 트랜잭션 밖에서 터지는 근본 원리
- [[jpql-query-basics]] — fetch join·집계 쿼리 작성
