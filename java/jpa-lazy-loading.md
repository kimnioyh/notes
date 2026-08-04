# JPA Lazy Loading & LazyInitializationException

**한 문장**: LAZY는 "연관 데이터를 진짜 쓸 때 가져오기"인데, 그 '쓸 때'가 영속성 컨텍스트(트랜잭션)가 닫힌 뒤면 가져올 통로가 없어서 `LazyInitializationException`이 터진다.

## 왜 헷갈렸나
- 엔티티를 잘 만들었는데 `event.getSessions()`가 어떨 땐 되고 어떨 땐 예외가 났다.
- "데이터가 분명 DB에 있는데 왜 못 읽지?"가 안 잡혔다. 문제는 데이터가 아니라 **읽는 타이밍과 통로(세션)** 였다.
- `@ManyToOne`은 기본이 LAZY인 줄 알았는데 사실 **EAGER**라 함정.

## 핵심

### 1. 영속성 컨텍스트 = 창고 + DB로 가는 통로
```
[내 코드] ←→ [영속성 컨텍스트(창고+통로)] ←→ [DB]
```
- `save()`, `findById()`로 꺼낸 엔티티는 이 창고에서 관리된다(= 영속 상태).
- 이 창고(통로)는 **트랜잭션이 살아있는 동안만** 열려 있다.

### 2. EAGER vs LAZY = 언제 가져오나
| 방식 | 뜻 | SQL 나가는 시점 |
|------|-----|----------------|
| EAGER(즉시) | 부모 꺼낼 때 자식도 무조건 같이 | `findById` 순간 |
| LAZY(지연) | 자식은 실제로 쓸 때까지 안 가져옴 | `getSessions()` 건드리는 순간 |

LAZY를 기본으로 쓰는 이유: 목록 100개 뿌리는데 매번 자식까지 다 끌어오면 DB가 죽는다. 필요할 때만 가져오려고.

### 3. LAZY는 "프록시(가짜 껍데기)"로 동작
LAZY 필드는 처음엔 진짜 목록이 아니라 **안 열어본 상자(프록시)** 가 들어있다.
그 상자를 **처음 접근하는 순간** DB로 통로를 뚫어 진짜 값을 채운다(= 초기화).

### 4. 예외가 터지는 두 조건
1. 프록시를 **아직 초기화 안 함** (상자 안 열어봄)
2. **영속성 컨텍스트가 이미 닫힘** (통로 없음)

→ 이 상태에서 상자를 열려 하면 💥 `LazyInitializationException`

### 5. 실무에서 만나는 지뢰
```
Controller → Service(@Transactional) → Repository
                 ↑ 여기서만 창고 열림
```
Service 메서드가 끝나면 창고 문 닫힘. 그 뒤 Controller가 `event.getSessions()`를 건드리면 → 이미 닫힘 → 💥. 스프링/JPA 초보 최다 실수 1순위.

### 6. ⚠️ 함정: @ManyToOne / @OneToOne 기본은 EAGER
- `@OneToMany` → 기본 LAZY (안전)
- `@ManyToOne`, `@OneToOne` → 기본 **EAGER** (위험) → 항상 `fetch = FetchType.LAZY` 명시

### 6-1. ⚠️ 더 깊은 함정: @OneToOne LAZY는 "주인 쪽이냐"에 따라 갈린다
`@OneToOne`의 LAZY는 어느 쪽에 붙었느냐로 동작이 갈린다.

- **주인 쪽(FK 컬럼 보유) @OneToOne → LAZY 잘 먹는다.** `@ManyToOne`과 똑같이 자기 FK 값만 보면 되니 프록시를 만들 수 있다.
- **역방향(mappedBy) @OneToOne → `bytecode enhancement` 없이는 LAZY가 안 먹고 즉시 로딩된다.** Hibernate가 이 필드에 `null`을 넣을지 프록시를 넣을지 정하려면 상대 row 존재 여부를 알아야 하는데, 그걸 판단하려고 결국 조회를 해버리기 때문.

Pulse의 `Report.event`는 `@JoinColumn(name="event_id")`로 FK를 가진 **주인 쪽**이라, 테스트로 확인하니 **진짜 LAZY 프록시로 로딩**됐다(`isLoaded=false`, 클래스가 `Event$HibernateProxy`).

> 🩹 처음엔 "detach 후 접근해도 예외가 안 난다 → 즉시 로딩됐다"고 잘못 판단했었다. 하지만 **detach는 즉시 로딩의 증거가 아니다** — 세션(트랜잭션)이 아직 열려 있으면 `detach(엔티티)`가 프록시를 확실히 끊지 못해, 접근하는 순간 그냥 초기화돼버린다. 그래서 LAZY 여부는 detach가 아니라 `PersistenceUnitUtil.isLoaded(entity, "필드명")`로 **직접** 확인해야 한다.

```java
PersistenceUnitUtil pu = em.getEntityManagerFactory().getPersistenceUnitUtil();
Report found = em.find(Report.class, id);   // 캐시 clear 후 다시 조회
assertThat(pu.isLoaded(found, "event")).isFalse();      // 아직 프록시 = LAZY 동작
found.getEvent().getTitle();                             // 여기서 초기화
assertThat(pu.isLoaded(found, "event")).isTrue();
```

### 7. 해결책 (원리 먼저, 적용은 나중)
- **Fetch Join** — 쿼리에서 "이번엔 자식까지 같이" 콕 집기
- **@EntityGraph** — 어노테이션으로 같은 효과
- **DTO 변환** — 창고 열려있을 때 필요한 값만 뽑아 담아 나가기(실무 최선호)

## 예시 코드
Pulse 프로젝트에서 예외를 **일부러 재현**한 테스트:

```java
@DataJpaTest  // 테스트 전체가 트랜잭션 안 → 평소엔 세션 열려있어 LAZY 접근 OK
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
class EventPersistenceTest {
    // ... 생성자 주입 ...

    @Test
    void 분리된_뒤_LAZY_접근하면_예외() {
        // 저장 후
        em.flush();
        em.clear(); // 캐시 비움 → findById가 DB에서 새로 읽고 sessions는 미초기화 프록시

        Event found = eventRepository.findById(id).orElseThrow();
        em.getEntityManager().detach(found); // ★ 창고에서 강제로 빼냄 = 통로 끊김

        // 프록시를 여는 순간, DB에서 가져와야 하는데 통로가 없다 → 💥
        assertThatThrownBy(() -> found.getSessions().size())
            .isInstanceOf(LazyInitializationException.class);
    }
}
```
`detach` = "이 엔티티를 영속성 컨텍스트에서 분리". 통로 끊긴 상태에서 프록시 초기화 시도 → 예외.

## 확인 문제
1. `LazyInitializationException`은 정확히 어떤 두 조건이 겹칠 때 터지나?
2. `@ManyToOne`을 그냥 두면 왜 위험한가?

<details><summary>답</summary>

1. **(a) LAZY 프록시가 아직 초기화되지 않았고, (b) 영속성 컨텍스트(세션)가 이미 닫혀서 DB로 갈 통로가 없을 때.** 둘 중 하나만이면 안 터진다 — 트랜잭션 안에서 접근하면(통로 살아있음) 초기화되고, 이미 초기화된 값이면(창고 닫혀도) 그냥 읽힌다.

2. `@ManyToOne` 기본이 **EAGER**라, 부모를 꺼낼 때마다 연관 부모가 줄줄이 즉시 로딩된다(Feedback→Session→Event→owner…). 필요 없는 조인/쿼리가 계속 나가 성능이 망가진다. 그래서 연관관계는 `fetch = FetchType.LAZY`로 깔고 시작한다.

</details>

## 더 볼 것
- [[jpa-association-mapping]] — 연관관계 매핑(주인, 양방향/단방향)
- N+1 문제, Fetch Join, @EntityGraph, OSIV(Open Session In View)
