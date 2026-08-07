# @DataJpaTest의 트랜잭션과 영속성 컨텍스트 (em·repository·수동 service가 한 tx를 공유하는 이유)

**한 문장**: `@DataJpaTest`는 **테스트 메서드 하나를 통째로 하나의 트랜잭션**으로 감싸고, 그 트랜잭션에는 **EntityManager(=영속성 컨텍스트) 딱 하나**가 스레드에 묶여 있어서 — `em`이든, repository든, 심지어 `new`로 직접 만든 service가 부른 repository든 — 그 tx 안의 모든 JPA 접근은 **같은 영속성 컨텍스트**를 통과한다.

## 왜 헷갈렸나

테스트에서 서비스를 이렇게 만들었다:

```java
eventService = new EventService(eventRepository, userRepository); // 스프링 빈이 아니라 생짜 객체
```

`new`로 만들었으니 스프링이 관리하는 빈이 아니다. 그런데도:
- 서비스 안 `create()`가 저장한 게 이어지는 `getPublic()`에서 보이고,
- `update()`의 setter 변경이 DB까지 반영되고(더티체킹),
- 지연 로딩(`event.getSessions()`)이 `LazyInitializationException` 없이 돈다.

"서비스에 `@Transactional`도 붙어있는데, `new`로 만들면 그게 먹긴 하나? 안 먹으면 왜 트랜잭션처럼 동작하지?" 여기가 안 잡혔다.

**결론부터**: 서비스의 `@Transactional`은 **안 먹는다(no-op)**. 트랜잭션은 서비스가 아니라 **`@DataJpaTest`가 걸어준 바깥 트랜잭션**이 제공하고, 모든 JPA 접근이 그 하나의 영속성 컨텍스트를 공유하기 때문에 위 현상이 일어난다.

## 핵심

### 1. `@DataJpaTest`는 테스트마다 트랜잭션을 열고 끝나면 롤백한다
`@DataJpaTest`는 내부에 `@Transactional`을 품고 있다. 그래서 각 `@Test` 메서드는:

```
@Test 시작 → [BEGIN 트랜잭션]
    ... 테스트 본문(persist, 서비스 호출, 조회) ...
@Test 끝   → [ROLLBACK]   ← 기본값이 롤백
```

- 롤백이 기본이라 테스트끼리 DB가 안 섞인다(그래서 매 테스트에서 같은 이메일로 User를 또 만들어도 됨).
- 이 "테스트 트랜잭션"이 이 노트의 주인공이다.

### 2. 트랜잭션 하나 = 영속성 컨텍스트(EntityManager) 하나
스프링 JPA는 트랜잭션이 시작될 때 **EntityManager 하나를 현재 스레드에 바인딩**한다(내부적으로 `TransactionSynchronizationManager`가 스레드-로컬로 들고 있음). 이 EntityManager가 곧 **영속성 컨텍스트(=1차 캐시)**다.

그 트랜잭션 안에서 JPA에 접근하는 모든 통로는 이 **스레드에 묶인 하나의 EntityManager로 합류**한다:
- **`TestEntityManager em`** → 이 tx의 EM에 위임
- **`EventRepository`(Spring Data 프록시 빈)** → "이미 열린 tx가 있으면 그 EM에 참여" → 같은 EM
- **`new EventService(...)`가 부른 `eventRepository.xxx()`** → 결국 위 repository → 같은 EM

즉 `em`, repository, 서비스가 부른 repository가 **전부 같은 영속성 컨텍스트**를 본다. 서비스가 빈이든 생짜든 상관없다 — 중요한 건 "지금 스레드에 열린 트랜잭션의 EM이 무엇이냐" 하나뿐.

```
        em ─┐
repository ─┼─▶ [이 테스트 tx의 EntityManager 1개 = 1차 캐시]
service→repo┘
```

### 3. 1차 캐시(영속성 컨텍스트)가 하는 일
영속성 컨텍스트는 그 tx 동안 다룬 엔티티를 **관리(managed) 상태**로 들고 있는 메모리 저장소다.
- `findByCode(code)`로 꺼낸 Event는 managed. 여기에 `setTitle(...)` 하면 컨텍스트가 "얘 바뀜"으로 표시 → 나중에 **자동으로 UPDATE 쿼리**를 만든다(**더티체킹**). `save()` 다시 안 불러도 됨.
- 같은 tx 안에서 **같은 PK를 또 조회하면 DB 안 가고 캐시의 그 객체를 그대로 돌려준다.** ← 이게 뒤의 flush/clear가 필요한 이유.
- 지연 로딩도 이 컨텍스트(=EM)가 살아있어야 추가 SELECT를 쏠 수 있다. tx가 닫히면 EM이 죽어서 `LazyInitializationException`.

### 4. `@Transactional`이 왜 no-op인가 — 프록시 기반이라서
`@Transactional`은 애너테이션 자체엔 힘이 없다. 스프링이 그 빈을 만들 때 **프록시로 감싸고**, 프록시가 메서드 앞뒤에 `BEGIN`/`COMMIT`(또는 `ROLLBACK`)을 끼워넣는 방식(AOP)이다.

```
정상 빈:   호출 → [프록시: BEGIN] → 진짜 메서드 → [프록시: COMMIT]
new 객체:  호출 → 진짜 메서드            ← 프록시가 없음 → BEGIN/COMMIT 없음 = @Transactional 무시
```

테스트에서 `new EventService(...)`는 프록시가 없는 생짜 객체라 `@Transactional`이 **그냥 주석처럼 무시**된다. 그런데도 트랜잭션처럼 도는 건, 앞서 말한 **`@DataJpaTest`의 바깥 트랜잭션**이 이미 열려 있고 서비스의 repository 호출이 거기에 **참여**하기 때문이다.

> 그래서 이 테스트는 "도메인 로직(쿼리·소유자검증·상태전이·매핑)"은 진짜로 검증하지만, **서비스 자신의 트랜잭션 경계(@Transactional을 제대로 붙였는지)**는 검증하지 못한다. 그건 프록시가 걸린 실제 빈이 필요하니 `@SpringBootTest`의 영역.

### 5. flush / clear — "진짜 DB에서 다시 읽게" 만드는 스위치
- **`flush()`**: 영속성 컨텍스트에 쌓인 변경(INSERT/UPDATE/DELETE)을 **DB로 밀어낸다.** 단 엔티티는 여전히 managed, 트랜잭션도 계속 열려 있음. (커밋 아님)
- **`clear()`**: 영속성 컨텍스트를 **비운다(모든 엔티티 detached).** 1차 캐시가 텅 빔.
- **`flush()` 다음 `clear()`** = "지금까지 쓴 걸 DB에 반영하고, 캐시는 비워서 **다음 조회가 캐시가 아니라 진짜 DB에서 새로 SELECT** 하게."

**왜 테스트에 넣나?** `clear()`를 안 하면, write 직후 다시 조회해도 캐시에 있는 **그 managed 객체**(이미 setter가 반영된 메모리 상태)를 돌려줘서, **실제로 DB에 안 써졌어도 테스트가 통과**할 수 있다. `flush+clear`로 강제 왕복시키면 "정말 DB에 반영됐는지"를 검증하게 된다.

## 예시 코드

이번 프로젝트 `EventServiceTest`(부분 수정 검증):

```java
@DataJpaTest
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
class EventServiceTest {

    private final EventRepository eventRepository;
    private final UserRepository userRepository;
    private final TestEntityManager em;
    private EventService eventService;

    // ... 생성자 주입(EventRepository, UserRepository, TestEntityManager) ...

    @BeforeEach
    void setUp() {
        // @DataJpaTest는 @Service 빈을 안 올리므로 실제 레포로 직접 조립.
        // 이 서비스의 @Transactional은 프록시가 없어 no-op — 트랜잭션은 아래 테스트가 제공.
        eventService = new EventService(eventRepository, userRepository);
    }

    @Test
    void 제목과_설명은_보낸_필드만_부분수정된다() {
        // [BEGIN] ← @DataJpaTest가 이 메서드를 트랜잭션으로 감쌈
        User ownerA = persistOwner("host@pulse.dev");
        String code = eventService.create(ownerA.getId(), new EventCreateRequest("title", "description")).code();

        // when: title만 수정(내부에서 findByCode→setTitle, 더티체킹 대기)
        eventService.update(ownerA.getId(), code, new EventUpdateRequest("nextTitle", null, null));

        em.flush(); // 쌓인 INSERT/UPDATE를 DB로 밀어냄
        em.clear(); // 1차 캐시 비움 → 다음 조회는 진짜 DB에서 새로 읽음

        // then: 캐시가 아니라 DB에서 새로 읽은 값으로 "실제 반영"을 검증
        EventView view = eventService.getPublic(code);
        assertThat(view.title()).isEqualTo("nextTitle");
        assertThat(view.description()).isEqualTo("description"); // 안 보낸 필드는 그대로
        // [ROLLBACK] ← 테스트 끝나면 자동 롤백, DB 원복
    }
}
```

- `em`, `eventRepository`, `eventService`가 부르는 repository가 **전부 이 테스트 tx의 같은 EntityManager**를 공유 → 그래서 `em.flush()`가 서비스가 저장한 것까지 밀어내고, `em.clear()` 뒤 `getPublic`이 DB에서 새로 읽는다.

## 확인 문제

1. 테스트에서 서비스를 `new EventService(...)`로 만들었는데도 `update()`의 setter 변경이 DB까지 반영된다. 서비스의 `@Transactional`이 먹어서일까? 아니라면 무엇 덕분인가?
2. write 직후 `em.clear()`를 **하지 않고** 같은 엔티티를 다시 조회하면, 테스트가 "실제 DB 반영"을 제대로 검증하지 못할 수 있다. 왜인가?

<details><summary>답</summary>

1. **아니다. 서비스의 `@Transactional`은 no-op이다.** `@Transactional`은 스프링이 빈을 프록시로 감싸야 동작하는데, `new`로 만든 생짜 객체엔 프록시가 없어 애너테이션이 무시된다. 그럼에도 반영되는 이유는 **`@DataJpaTest`가 테스트 메서드 전체를 트랜잭션으로 감싸고, 그 트랜잭션에 바인딩된 하나의 EntityManager(영속성 컨텍스트)를 서비스의 repository 호출이 공유**하기 때문이다. `update()`가 꺼낸 Event는 이 컨텍스트의 managed 엔티티라 `setTitle` 시 더티체킹으로 UPDATE가 예약되고, tx가 살아있는 동안 flush/커밋 시 DB에 반영된다.

2. `clear()`를 안 하면 재조회 시 **DB로 왕복하지 않고 1차 캐시에 있는 그 managed 객체를 그대로** 돌려준다. 그 객체는 이미 메모리에서 `setTitle`이 반영된 상태라, **설령 DB로의 flush/write가 잘못됐어도** 어서션이 통과해버릴 수 있다. `flush()`로 DB에 밀어내고 `clear()`로 캐시를 비워 강제로 새 SELECT를 유도해야 "정말 DB에 저장됐다"를 검증할 수 있다.

</details>

## 더 볼 것

- `jpa-lazy-loading` — 지연 로딩이 왜 tx(영속성 컨텍스트)가 열려 있어야 되는지
- `spring-test-constructor-injection` — `@TestConstructor(ALL)`로 테스트에 repository·`em`을 생성자 주입받는 법
- `spring-05-di-autowired` — 프록시/빈이 왜 DI로 와야 `@Transactional` 같은 게 동작하는지
