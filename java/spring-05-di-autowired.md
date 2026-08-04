# 의존관계 자동 주입 (@Autowired)

**한 문장**: 컴포넌트 스캔으로 등록한 빈들은 `@Bean`처럼 코드로 의존관계를 못 엮으므로, `@Autowired`가 **필요한 타입의 빈을 컨테이너에서 찾아 대신 넣어준다(DI)**.

> 출처: 김영한 스프링 핵심 기본편 섹션 6~7. (이노스트림 Day 25)

## 왜 필요한가
- `@ComponentScan`은 빈을 **등록**만 한다. `AppConfig`의 `@Bean`처럼 "이 빈에 저 빈을 주입"을 코드로 지정할 자리가 없다.
- 그래서 "이 자리엔 이 타입 빈을 넣어줘"라고 스프링에 맡기는 표식이 `@Autowired`.

## 핵심

### 1. 생성자 주입 (★ 권장)
```java
@Service
public class MemberServiceImpl implements MemberService {

    private final MemberRepository memberRepository;   // final 가능

    @Autowired  // 생성자가 1개면 생략 가능
    public MemberServiceImpl(MemberRepository memberRepository) {
        this.memberRepository = memberRepository;      // 컨테이너가 맞는 빈을 주입
    }
}
```
- 김영한 권장 = **생성자 주입**. 이유:
  - **불변**: `final`로 한 번 주입 후 안 바뀜.
  - **필수 보장**: 의존성 없으면 객체 생성 자체가 안 됨(누락을 컴파일/기동 시점에 잡음).
  - **테스트 쉬움**: 스프링 없이 `new`로 목(mock) 주입 가능.
- **생성자가 1개뿐이면 `@Autowired` 생략** 가능.

### 2. 다른 주입 방법 (비권장)
- **필드 주입** (`@Autowired private X x;`): 간단하지만 테스트·불변에 불리 → 지양.
- **수정자(setter) 주입**: 선택적·변경 가능한 의존성에만 제한적으로.

### 3. ⚠️ 주입 대상 빈이 2개 이상이면 충돌
같은 타입 빈이 여러 개면 스프링이 뭘 넣을지 몰라 에러(`NoUniqueBeanDefinitionException`). 해결:
- `@Primary`: 여러 개 중 **기본** 하나 지정.
- `@Qualifier("이름")`: 주입 지점에서 **콕 집어** 선택.

## 예시로 남는 그림
```
컴포넌트 스캔: MemberServiceImpl, MemoryMemberRepository 를 빈 등록
                       │
@Autowired: MemberServiceImpl 생성자에 필요한
            MemberRepository 타입 빈을 컨테이너에서 찾아 주입
```

## 확인 문제
1. 김영한이 권장하는 주입 방식과 그 이유 3가지는?
2. 같은 타입 빈이 2개일 때 주입 충돌을 푸는 방법은?

<details><summary>답</summary>

1. **생성자 주입**. ① 불변(`final`), ② 의존성 필수 보장(없으면 객체 생성 실패라 누락을 일찍 잡음), ③ 스프링 없이 `new`로 목 주입이 되어 테스트가 쉬움. (+ 생성자 1개면 `@Autowired` 생략 가능)
2. `@Primary`로 기본 빈을 정하거나, 주입 지점에 `@Qualifier("빈이름")`로 특정 빈을 지정한다.

</details>

## 더 볼 것
- [[spring-04-component-scan]] — 자동 빈 등록
- [[spring-01-concepts]] — DI/IoC 개요, 레이어드 아키텍처
- [[spring-test-constructor-injection]] — 테스트에서의 생성자 주입(@TestConstructor)
