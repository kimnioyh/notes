# JPA 연관관계 매핑 (주인 · 양방향/단방향)

**한 문장**: 두 엔티티를 잇는 FK는 한쪽만 들고(= 연관관계 주인), 나머지 한쪽은 `mappedBy`로 "난 주인 아니고 반대편이 관리해"라고 선언하는 게 JPA 연관관계 매핑이다.

## 왜 헷갈렸나
- Session이 `eventId`(숫자)를 들어야 하나, `Event`(객체)를 들어야 하나?
- 양방향으로 서로 참조하게 하면 좋은 건 줄 알았는데, 왜 다들 단방향부터 하라고 할까?
- `mappedBy`에 뭘 적어야 하는지, 왜 오타 나도 컴파일은 되는지.

## 핵심

### 1. 객체는 FK 숫자가 아니라 "상대 객체"를 들고 있는다
```java
// ❌ eventId 숫자를 직접 들지 않는다
// ✅ Event 객체 참조를 든다
@ManyToOne(fetch = FetchType.LAZY, optional = false)
@JoinColumn(name = "event_id")  // DB엔 event_id FK 컬럼으로 저장
private Event event;
```
`optional = false` = 이 FK는 NOT NULL(항상 부모가 있어야 함).

### 2. 연관관계 주인 = FK 컬럼을 들고 있는 쪽
- FK를 가진 쪽(`@ManyToOne` 붙은 쪽, 보통 자식)이 **주인**. INSERT/UPDATE 시 이 값으로 FK가 정해진다.
- 반대쪽(`@OneToMany`)은 **주인이 아님** → `mappedBy`로 표시.
```java
// Event (부모, 주인 아님)
@OneToMany(mappedBy = "event", cascade = CascadeType.ALL, orphanRemoval = true)
private List<Session> sessions = new ArrayList<>();
```
`mappedBy = "event"`의 `"event"`는 **자식 쪽 필드 이름**(Session.event). "FK 관리는 Session.event가 한다"는 뜻.

### 3. ⚠️ mappedBy는 문자열이라 오타가 런타임에 터진다
`mappedBy = "evnet"`처럼 오타 나도 **컴파일은 통과**하고, 앱 뜰 때 Hibernate 메타모델 만들다가 터진다. 컴파일러가 안 잡아주는 지뢰.

### 4. 양방향 vs 단방향 — 기본은 단방향
양방향(서로 참조)은 편해 보이지만 관리 포인트가 늘고 무한루프(toString/직렬화) 위험이 있다. **꼭 필요할 때만** 양방향.

양방향으로 둘 기준(대략 다 충족될 때):
- 부모 객체에서 자식 목록을 자주 순회한다
- 자식 컬렉션이 **작고 유한**하다(수백 개 넘지 않음)
- 부모를 통해 자식을 cascade로 저장/삭제한다

Pulse의 선택:
| 관계 | 방향 | 이유 |
|------|------|------|
| Event ↔ Session | **양방향** | aggregate 경계, cascade+순회 |
| User → Event | 단방향 | User가 Event 목록 순회할 일 없음 |
| Session → Feedback | 단방향 | Feedback이 많고, 부모서 역순회 불필요 |
| Report → Event | 단방향 | @OneToOne, Report가 Event 참조만 |

### 5. cascade & orphanRemoval
- `cascade = ALL` — 부모 저장/삭제가 자식까지 전파(Event save → Session도 함께 save).
- `orphanRemoval = true` — 부모 컬렉션에서 자식을 빼면 그 자식 row도 삭제.
- **주의**: 진짜 "부모가 자식 생명주기를 소유"할 때만. 공유되는 엔티티엔 걸면 안 됨.

### 6. 양방향이면 편의 메서드로 양쪽 동기화
```java
public void addSession(Session s) {
    sessions.add(s);      // 부모 컬렉션에 추가
    s.setEvent(this);     // 자식의 FK도 세팅  ← 둘 다 해야 일관성 유지
}
```

## 예시 코드
Session 엔티티 (자식 = 주인):
```java
@Entity
@Table(name = "sessions")  // 'session'류 예약어 회피 겸 복수형
public class Session {
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "event_id")
    private Event event;                 // Event 객체를 든다(주인)

    @Column(name = "session_order")      // 'order'는 SQL 예약어 → 컬럼명 변경
    private Integer order;
}
```

## @ElementCollection — 값 컬렉션을 별도 테이블에 (엔티티 아닌 것들)
`List<String> keywords`처럼 **엔티티가 아닌 값(문자열·enum 등)의 컬렉션**은 `@ManyToOne`/`@OneToMany`가 아니라 `@ElementCollection`으로 매핑한다. 별도 엔티티/PK가 없고, **원소마다 한 행인 딸린 테이블**에 저장된다.

```java
@ElementCollection
private List<String> keywords;   // 기본 테이블명 feedback_keywords
```
```
feedbacks               feedback_keywords
┌────┐                  ┌─────────────┬──────────┐
│ id │                  │ feedback_id │ keywords │  ← 키워드 하나당 한 행
├────┤                  ├─────────────┼──────────┤
│ 1  │                  │ 1           │ 발표속도 │
└────┘                  │ 1           │ 내용     │
```

- **기본 LAZY** — 실제로 건드릴 때 로딩(트랜잭션 밖이면 [[jpa-lazy-loading]] 예외, 목록이면 [[jpa-n-plus-one-and-osiv]]).
- **JPQL 조인으로 펼쳐 집계** — 컬렉션이 딴 테이블이라, "값별 개수"를 세려면 조인해 각 원소를 꺼낸다:
  ```jpql
  select new KeywordCount(k, count(k))
  from Feedback f join f.keywords k   -- 컬렉션을 원소 k로 펼침((f, k) 짝으로 행 뻥튀기)
  group by k order by count(k) desc   -- 다시 묶어서 센다
  ```
- **언제 쓰나**: 별도 키워드 테이블/엔티티까지 둘 필요 없는 단순 값 목록. 정규화 오버엔지니어링을 피하는 선택. 다른 엔티티가 그 값을 참조·조회해야 하면 그때 정식 엔티티로 승격.

## 확인 문제
1. `@OneToMany(mappedBy = "event")`에서 `"event"`는 무엇을 가리키나?
2. 연관관계 주인은 어느 쪽이고, 왜 그 개념이 필요한가?
3. `List<String> keywords`를 `@ElementCollection`으로 두면 DB에 어떻게 저장되고, "키워드별 빈도"는 JPQL로 어떻게 세나?

<details><summary>답</summary>

1. **반대편(자식) 엔티티의 필드 이름.** 여기선 `Session.event` 필드를 가리킨다. "FK 관리는 저 필드가 하고, 나(부모 컬렉션)는 읽기용 역방향일 뿐"이라는 선언. 문자열이라 오타 시 런타임에 터진다.

2. **FK 컬럼을 실제로 들고 있는 쪽(보통 `@ManyToOne`이 붙은 자식).** DB에는 관계를 나타내는 FK가 한 개뿐인데, 양쪽 객체가 서로를 참조하면 "둘 중 누구 값으로 FK를 INSERT/UPDATE할지" 정해야 한다. 그 기준이 주인. 주인이 아닌 쪽(`mappedBy`)의 값 변경은 DB에 반영되지 않는다.

3. 엔티티가 아닌 값 컬렉션이라 별도 딸린 테이블(`feedback_keywords`)에 **원소마다 한 행**(`feedback_id`, `keywords`)으로 저장된다. 빈도는 `from Feedback f join f.keywords k`로 컬렉션을 원소 `k`로 펼친 뒤(한 소감이 키워드 N개면 N행으로 뻥튀기) `group by k`로 다시 묶어 `count(k)`로 센다.

</details>

## 더 볼 것
- [[jpa-lazy-loading]] — LAZY 로딩과 예외
- 연관관계 주인만 변경하면 FK 반영, mappedBy 쪽만 바꾸면 반영 안 되는 실수
