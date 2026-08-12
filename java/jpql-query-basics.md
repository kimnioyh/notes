# JPQL @Query 작성 기초 (Spring Data JPA)

**한 문장**: JPQL은 테이블·컬럼이 아니라 **엔티티·필드**로 쓰는 객체지향 쿼리라, 단순 조회는 메서드 이름(파생 쿼리)으로, 집계·조인은 `@Query`로 짜며, 컴파일러가 문자열을 검증하지 않으므로 **부팅(런타임)에서야 오류가 드러난다.**

## 왜 헷갈렸나
집계 쿼리를 짜다 `from feedback f`(소문자), `where ... = ownerId`(콜론 없음)처럼 썼는데 **컴파일은 통과**하고, 테스트를 돌리자 긴 스택트레이스(컨텍스트 로드 실패)가 떴다. `@Query`가 그냥 문자열이라 자바 컴파일러는 안 보고, Hibernate가 부팅 시 파싱하다 터진 것. "컴파일 됐으니 맞겠지"가 함정이었다.

## 핵심

### 1. 쿼리 만드는 3가지 방법
| 방법 | 어떻게 | 언제 |
|---|---|---|
| 파생 쿼리 | 메서드 **이름** (`findByStatusOrderByCreatedAtDesc`) | 단순 조회·정렬. **집계 불가** |
| `@Query` (JPQL) | 쿼리 문자열 | 집계·조인. 대부분 여기 |
| `@Query` (native) | 진짜 SQL (`nativeQuery=true`) | JPQL로 안 되는 DB 특화 |

파생 쿼리는 `And` 뒤에 **또 다른 속성**이 와야 한다: `findByStatusAndOrderBy...`는 깨지고(“And 다음 뭘 거를지 없음”), `findBySession_IdAndStatusOrderByCreatedAtDesc`처럼 `And Status`가 있어야 성립. 연관은 `_`로 탐색(`Session_Id`).

### 2. JPQL은 엔티티·필드로 쓴다 (테이블 아님, 대소문자 구분)
```jpql
from Feedback f          -- ✅ 엔티티 클래스명 Feedback (테이블 feedbacks 아님, 소문자 아님)
where f.session.id = ... -- ✅ 필드를 점으로 타고 감(연관 자동 조인). f.session_id(컬럼) 아님
```
`from feedback`(소문자)은 "그런 엔티티 없음"으로 부팅 실패.

### 3. 파라미터는 `:이름` + `@Param`, 콜론 필수
```java
where f.session.event.owner.id = :ownerId   -- ✅ 콜론
where f.session.event.owner.id = ownerId    -- ❌ ownerId를 필드 경로로 오인 → 부팅 실패
```
```java
List<..> q(@Param("ownerId") Long ownerId);  // 쿼리의 :ownerId와 이름 일치(대소문자까지)
```

### 4. GROUP BY 집계 — Object[] 또는 constructor expression
- 여러 컬럼 선택 → `List<Object[]>` (각 행이 `[값, 값]`), 서비스에서 꺼내 분배.
  - **0건인 그룹은 행이 아예 없다** → 인덱스로 `get(0)`을 특정 값이라 가정 금지. `row[0]`을 보고 분배하고, 변수는 0으로 초기화.
- 바로 DTO로 → **constructor expression**: `select new com.x.KeywordCount(k, count(k))`. FQN 필요.
  - **`count()`는 Long** → `int` 생성자에 안 맞으면 `cast(count(k) as integer)`.

### 5. limit은 Pageable로
```java
List<Feedback> recent(..., Pageable pageable);  // 쿼리엔 limit 없음
// 호출: recent(..., PageRequest.of(0, 50))  // 0페이지 50개 = LIMIT 50
```

### 6. 선택적 필터 관용구 `(:x is null or ...)` — nullable 파라미터로 조건 on/off
필터가 있으면 적용, 없으면 무시하는 걸 한 쿼리로:
```java
where (:sessionId is null or f.session.id = :sessionId)
  and (:toxic     is null or f.toxic     = :toxic)
```
- `:x`가 null이면 앞 `is null`이 참 → 뒤 조건 무시(= 필터 안 걸림).
- **핵심 함정: 파라미터는 래퍼 타입**이어야 한다. `(:toxic is null ...)`을 쓰려면 `Boolean toxic`(null 가능). `boolean`(primitive)은 null이 될 수 없어 필터가 항상 걸리고, 서비스가 null을 넘기면 언박싱 NPE. 같은 이유로 `Long`·`Integer` 래퍼 사용.
- boolean 플래그로 상태 좁히기: `(:includeHidden = true or f.status = com.x.FeedbackStatus.VISIBLE)` — true면 전체, false면 VISIBLE만.

### 7. `@Query`는 런타임 검증 → 실행 테스트로 확인
컴파일은 문자열이라 통과. 유효성은 **부팅 시** Hibernate가 파싱하며 검증하고, 결과 매핑·파라미터 바인딩은 **실제 실행**해야 드러난다. `select f`(Feedback)를 `List<FeedbackView>`로 받거나 `@Param("SessionId")` 오타 같은 건 부팅은 통과하고 **호출 시** 터진다. → JPQL 짜면 **컨텍스트 띄우는 테스트 + 실제 실행 테스트** 둘 다 필요. ("부팅 통과 ≠ 동작")

## 예시 코드
Pulse 집계·모더레이션 레포:
```java
// GROUP BY + Object[]
@Query("""
    select f.sentiment, count(f) from Feedback f
    where f.session.event.code = :eventCode
      and (:sessionId is null or f.session.id = :sessionId)
      and f.status = :status
    group by f.sentiment
    """)
List<Object[]> countBySentiment(@Param("eventCode") String eventCode,
                                @Param("sessionId") Long sessionId,
                                @Param("status") FeedbackStatus status);

// constructor expression + cast + join(@ElementCollection) + Pageable
@Query("""
    select new com.hancome.pulse.feedback.dto.KeywordCount(k, cast(count(k) as integer))
    from Feedback f join f.keywords k
    where f.session.event.code = :eventCode and f.status = :status
    group by k order by count(k) desc
    """)
List<KeywordCount> topKeywords(..., Pageable pageable);  // PageRequest.of(0,10)

// 선택적 필터 여러 개 + 래퍼 타입
@Query("""
    select f from Feedback f
    where f.session.event.owner.id = :ownerId
      and (:eventCode is null or f.session.event.code = :eventCode)
      and (:toxic is null or f.toxic = :toxic)
      and (:includeHidden = true or f.status = com.hancome.pulse.feedback.FeedbackStatus.VISIBLE)
    order by f.createdAt desc
    """)
List<Feedback> adminList(@Param("ownerId") Long ownerId, @Param("eventCode") String eventCode,
                         @Param("toxic") Boolean toxic, @Param("includeHidden") boolean includeHidden);
```

## 확인 문제
1. `from feedback f`, `= ownerId`가 컴파일은 통과하고 테스트에서 터지는 이유는? 각각 뭐가 틀렸나?
2. 선택적 필터 `(:toxic is null or f.toxic = :toxic)`에서 파라미터 타입을 `boolean`으로 하면 무슨 일이 나나? 왜 `Boolean`이어야 하나?
3. constructor expression에 `count(k)`를 바로 넣으면 왜 타입 오류가 날 수 있고, 어떻게 푸나?

<details><summary>답</summary>

1. `@Query`는 문자열이라 자바 컴파일러가 검증하지 않아 컴파일은 통과하고, Hibernate가 부팅 시 파싱하다 터진다. `feedback`(소문자)은 엔티티명이 아니라(엔티티는 `Feedback`) "그런 엔티티 없음"이고, `= ownerId`는 콜론이 없어 파라미터가 아니라 필드 경로로 해석돼 실패한다. → `from Feedback f`, `= :ownerId`.

2. `boolean`(primitive)은 null이 될 수 없어 `:toxic is null`이 항상 거짓 → 필터가 항상 적용되고, 서비스가 "필터 안 함"으로 null을 넘기면 언박싱하다 NPE가 난다. null 체크로 조건을 끄려면 null을 담을 수 있는 래퍼 `Boolean`이어야 한다.

3. `count()`는 Long을 반환하는데 DTO 생성자가 `int`면 "맞는 생성자 없음"이 된다. `cast(count(k) as integer)`로 int로 변환해 넘기면 된다.

</details>

## 더 볼 것
- [[jpa-association-mapping]] — `@ElementCollection` 조인(`join f.keywords k`)
- [[jpa-n-plus-one-and-osiv]] — 조회 결과의 LAZY 연관과 N+1
- [[datajpatest-transaction-and-persistence-context]] — @Query를 실제 실행으로 검증하는 슬라이스 테스트
