# 컴포넌트 스캔 (@ComponentScan)

**한 문장**: `@ComponentScan`은 `@Component`가 붙은 클래스를 **자동으로 찾아 빈으로 등록**해줘서, `AppConfig`에 `@Bean`을 일일이 안 써도 되게 한다.

> 출처: 김영한 스프링 핵심 기본편 섹션 6. (이노스트림 Day 25)

## 왜 필요한가
- 빈이 수십·수백 개면 `AppConfig`에 `@Bean` 메서드를 하나하나 쓰는 게 노가다 + 누락 위험.
- 클래스에 표식(`@Component`)만 붙여두면 스프링이 알아서 긁어 등록하게 하자 = 컴포넌트 스캔.

## 핵심

### 1. 자동 등록
```java
@Component               // 이 표식만 있으면 스캔 대상 → 빈 자동 등록
public class MemberServiceImpl implements MemberService { ... }
```
- `@Controller`, `@Service`, `@Repository`, `@Configuration`도 **내부에 `@Component`를 품고 있어** 전부 스캔 대상이다.

### 2. 탐색 시작 위치
```java
@Configuration
@ComponentScan(basePackages = "com.hancome.pulse")   // 없으면 default
public class AppConfig { }
```
- `basePackages`를 안 주면 **`@ComponentScan`이 붙은 클래스의 패키지**부터 하위 전체를 스캔.
- 그래서 관례상 **설정/시작 클래스를 프로젝트 최상단 패키지**에 둔다 → 그 아래가 통째로 스캔됨.
- 스프링 부트의 `@SpringBootApplication` **안에 이미 `@ComponentScan`이 포함**돼 있어서, 메인 클래스 패키지 하위가 자동 스캔된다(그래서 부트는 따로 설정 안 해도 됨).

### 3. 필터로 제외/포함
```java
@ComponentScan(
    excludeFilters = @ComponentScan.Filter(
        type = FilterType.ANNOTATION, classes = Configuration.class))
```
- `excludeFilters`로 특정 애노테이션/타입을 스캔에서 뺀다(예: 예제에서 수동 `@Configuration` 충돌 피하려 제외). `includeFilters`도 있음.

### 4. ⚠️ 빈 이름 중복
- **자동 vs 자동**: 같은 이름 빈이 둘이면 → 스프링 부트 기동 시 **충돌 에러**(`ConflictingBeanDefinitionException`).
- **자동 vs 수동(@Bean)**: 원래는 수동이 자동을 오버라이드(수동 우선)하지만, **스프링 부트는 기본적으로 이 오버라이드를 막아둬서** 역시 에러로 알려준다(명시적으로 켜야 허용).

## 확인 문제
1. `@ComponentScan(basePackages=...)`를 지정 안 하면 어디서부터 스캔하나?
2. `@Service`는 왜 컴포넌트 스캔 대상이 되나?

<details><summary>답</summary>

1. `@ComponentScan`(또는 `@SpringBootApplication`)이 **붙은 클래스의 패키지**를 기준으로 그 하위 전체를 스캔한다. 그래서 시작 클래스를 최상단 패키지에 두는 게 관례.
2. `@Service`(그리고 `@Controller`/`@Repository`/`@Configuration`) 애노테이션 내부에 **`@Component`가 메타 애노테이션으로 포함**돼 있어서, 컴포넌트 스캔이 이들을 모두 대상으로 인식한다.

</details>

## 더 볼 것
- [[spring-02-container-and-bean]] — @Bean 수동 등록 방식
- [[spring-05-di-autowired]] — 자동 등록된 빈들의 의존관계를 @Autowired로 주입
