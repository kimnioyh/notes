# 스프링 컨테이너와 빈 — 어떻게 만들어지나

**한 문장**: 스프링 컨테이너는 `AppConfig` 같은 **구성 정보**를 읽어 (빈 이름 → 빈 객체) 목록을 만들고, 그 다음 빈들끼리의 **의존관계를 주입(DI)** 해주는 상자다.

> 출처: 김영한 스프링 핵심 기본편 섹션 5. (이노스트림 Day 25)
> `spring-01-concepts`가 "빈/컨테이너가 뭔지" 개요라면, 이 노트는 "그 컨테이너가 실제로 어떤 순서로 만들어지나" 내부 동작.

## 왜 알아야 하나
- `ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);` 한 줄에 사실 **두 단계**(빈 등록 → 의존관계 주입)가 숨어 있다. 이걸 뭉뚱그리면 나중에 "빈은 있는데 주입이 안 됐다" 같은 상황이 안 잡힌다.
- `@Bean` 방식(직접 등록)과 `@ComponentScan`(자동 등록)이 왜 갈라지는지도 이 그림에서 출발한다.

## 핵심

### 1. 컨테이너 = ApplicationContext
- `ApplicationContext`가 곧 **스프링 컨테이너**(빈을 담는 상자).
- `BeanFactory`(기본 기능) ← `ApplicationContext`(그걸 상속 + 부가기능). 실무에선 그냥 `ApplicationContext`를 컨테이너라 부른다.

### 2. 만들어지는 순서 (★ 두 단계)
```
new AnnotationConfigApplicationContext(AppConfig.class)
        │
   ┌────┴───────────────────────────┐
   1) 빈 등록                         2) 의존관계 주입(DI)
   AppConfig의 @Bean 메서드를 호출해   등록된 빈들끼리
   (빈 이름 → 빈 객체) 목록에 저장      서로 연결(주입)
```
- **1단계 – 빈 등록**: 구성 정보(`AppConfig`)의 `@Bean`을 읽어, `빈 이름`(기본=메서드명)과 `빈 객체`를 컨테이너에 저장.
- **2단계 – 의존관계 주입**: 빈들 사이의 의존관계를 채워 넣음(DI).

> 📌 자바 코드로 등록하는 `@Bean` 방식은 메서드를 **호출하는 순간 의존관계까지 바로 연결**되므로, 위 1·2단계가 사실상 한 번에 일어난다. (단계가 뚜렷이 갈리는 건 뒤에 나올 컴포넌트 스캔 + `@Autowired` 방식.)

### 3. 구성 정보(AppConfig)의 역할
```java
@Configuration
public class AppConfig {

    @Bean
    public MemberService memberService() {
        return new MemberServiceImpl(memberRepository()); // ← 의존관계를 여기서 엮음
    }

    @Bean
    public MemberRepository memberRepository() {
        return new MemoryMemberRepository();
    }
}
```
- `AppConfig`는 "무엇을 빈으로 만들고, 무엇을 무엇에 주입할지"를 **한곳에 모은 설계도**.
- 구현체 교체(`Memory…` → `Db…`)가 이 파일 한 곳에서 끝난다 → 사용처 코드는 안 건드림.

### 4. 조회
```java
ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
MemberService svc = ctx.getBean("memberService", MemberService.class);
```
- 이름 + 타입으로 꺼낸다. **빈 이름은 유일**해야 하고, 겹치면 충돌.

## 예시로 남는 그림
```
[AppConfig] --읽음--> [스프링 컨테이너]
                        ├─ "memberService"  → MemberServiceImpl 객체
                        └─ "memberRepository"→ MemoryMemberRepository 객체
                              ↑ 둘 사이 의존관계(주입) 완료
```

## 확인 문제
1. `new AnnotationConfigApplicationContext(AppConfig.class)` 한 줄이 내부적으로 하는 **두 가지 일**은?
2. 빈 이름의 기본값은 무엇으로 정해지나?

<details><summary>답</summary>

1. **① 빈 등록**(구성 정보의 `@Bean`을 읽어 이름→객체 목록 저장), **② 의존관계 주입(DI)**(등록된 빈들끼리 연결). 자바 `@Bean` 방식은 이 둘이 한 번에 일어난다.
2. `@Bean`이 붙은 **메서드 이름**(예: `memberService()` → `"memberService"`). `@Bean(name="...")`로 바꿀 수 있다.

</details>

## 더 볼 것
- [[spring-01-concepts]] — 빈/DI/레이어드 전체 개요
- [[spring-03-singleton-container]] — 컨테이너가 빈을 왜 싱글톤으로 관리하나, `@Configuration`+CGLIB
- 뒤 섹션: 컴포넌트 스캔(`@ComponentScan`)으로 빈을 자동 등록하는 방식
