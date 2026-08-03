# 스프링 테스트 생성자 주입 & @TestConstructor

**한 문장**: 스프링 테스트 클래스에서 생성자로 빈을 주입받으려면 `@TestConstructor(autowireMode = ALL)`이 필요하다 — 없으면 JUnit이 생성자 파라미터를 못 채워 `ParameterResolutionException`이 난다.

## 왜 헷갈렸나
- `@DataJpaTest` 붙이고 생성자에 `EventRepository`, `TestEntityManager`를 받았는데 실행하면 `ParameterResolutionException: No ParameterResolver registered for parameter ...`.
- 프로덕션 코드에선 생성자 주입이 그냥 되는데 테스트에선 왜 안 되지?

## 핵심

### 1. 원인: JUnit과 스프링의 역할 경계
- 테스트 객체를 **누가 만드나?** → JUnit Jupiter가 만든다.
- JUnit은 기본적으로 생성자 파라미터를 **스프링 빈으로 자동 주입하지 않는다.** 그래서 "이 파라미터 누가 채우지?" 하고 `ParameterResolutionException`.

### 2. 해결: @TestConstructor(autowireMode = ALL)
```java
@DataJpaTest
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
class EventPersistenceTest { ... }
```
- `ALL` = 생성자의 **모든 파라미터를 스프링 빈으로 자동 주입**하라.
- 이걸 붙이면 스프링이 생성자 주입을 넘겨받아 빈을 채운다.
- (대안) `spring.test.constructor.autowire.mode=all` 프로퍼티로 전역 설정도 가능.

### 3. 왜 굳이 생성자 주입?
필드 주입(`@Autowired` 필드)도 되지만, 생성자 주입은 **불변(final) 필드 + 명확한 의존성**이라 프로덕션 코드 정석과 같다. 테스트도 같은 스타일로 통일.

### 4. (곁다리) Spring Boot 4 테스트 슬라이스 패키지 재편
Boot 4에서 테스트 어노테이션 패키지가 바뀌었다. Boot 3 기억으로 import하면 `ClassNotFound`/`package does not exist`:
```java
// Boot 4
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
// (Boot 3은 org.springframework.boot.test.autoconfigure.orm.jpa.* 였음)
```

## 예시 코드
```java
@DataJpaTest
@TestConstructor(autowireMode = TestConstructor.AutowireMode.ALL)
class EventPersistenceTest {

    private final EventRepository eventRepository;
    private final TestEntityManager em;

    // ↓ 이 파라미터들을 스프링이 빈으로 채워준다 (@TestConstructor ALL 덕분)
    EventPersistenceTest(EventRepository eventRepository, TestEntityManager em) {
        this.eventRepository = eventRepository;
        this.em = em;   // 필드에 저장해야 @Test 메서드에서 쓸 수 있다
    }

    @Test
    void 저장_조회() {
        User owner = new User("host@pulse.dev", "pw");
        em.persist(owner);                       // UserRepository 없이 직접 영속화
        Event e = new Event("EVT-001", "제목", "설명", owner);
        eventRepository.save(e);
        // ...
    }
}
```

## 확인 문제
1. 생성자 주입 테스트에서 `ParameterResolutionException`이 나는 근본 원인은?
2. `@TestConstructor(autowireMode = ALL)`은 정확히 무엇을 시키나?

<details><summary>답</summary>

1. 테스트 객체를 **JUnit Jupiter가 생성**하는데, JUnit은 기본적으로 생성자 파라미터를 스프링 빈으로 자동 주입하지 않기 때문. "이 파라미터를 채울 ParameterResolver가 없다"고 예외를 낸다.

2. 스프링에게 **테스트 클래스 생성자의 모든 파라미터를 스프링 빈으로 자동 주입(autowire)** 하라고 지시. 그러면 스프링의 `SpringExtension`이 파라미터 해석을 넘겨받아 각 파라미터에 맞는 빈을 주입한다.

</details>

## 더 볼 것
- [[jpa-lazy-loading]], [[jpa-association-mapping]]
- 필드 주입 vs 생성자 주입, `@DataJpaTest`가 띄우는 빈 범위(슬라이스 테스트)
