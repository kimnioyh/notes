# 싱글톤 컨테이너와 @Configuration

**한 문장**: 스프링 컨테이너는 빈을 **싱글톤(딱 1개)** 으로 만들어 공유하므로, 싱글톤 패턴을 직접 구현하는 고통 없이 객체 하나를 재사용한다. 단 그 공유 객체를 **stateful하게 쓰면 사고**가 난다.

> 출처: 김영한 스프링 핵심 기본편 섹션 5~6. (이노스트림 Day 25)

## 왜 필요한가
- 웹앱은 같은 요청이 초당 수백 번 온다. 요청마다 `new`로 객체를 만들면 객체가 폭증한다.
- 그래서 "객체 1개만 만들어 공유"(싱글톤)가 필요한데, 직접 구현하면 `private` 생성자·정적 필드로 코드가 지저분해지고 DIP/OCP 위반 + 테스트가 어렵다.
- **스프링 컨테이너가 이 싱글톤 관리를 대신** 해준다 → 패턴의 단점 없이 객체 1개 공유.

## 핵심

### 1. 컨테이너 빈 = 싱글톤
```java
MemberService a = ctx.getBean(MemberService.class);
MemberService b = ctx.getBean(MemberService.class);
// a == b  (같은 인스턴스)
```
- 기본 스코프가 싱글톤이라, 몇 번을 꺼내도 **같은 객체**.

### 2. ⚠️ 싱글톤은 무상태(stateless)로 설계
공유 객체에 **특정 요청 값**을 필드로 저장하면, 다른 요청이 그 값을 덮어써서 터진다.
```java
public class StatefulService {
    private int price;                 // ❌ 공유 필드에 상태 저장
    public void order(int price){ this.price = price; }
    public int getPrice(){ return price; }
}
```
- A가 10000원 주문 → B가 20000원 주문 → **A가 자기 값을 조회하면 20000원**이 나온다(공유 필드가 덮여서).
- 해결: 필드에 상태를 두지 말고 **지역변수·파라미터·반환값**으로만 처리.

### 3. @Configuration + CGLIB — 싱글톤을 지켜주는 장치
`@Bean` 메서드끼리 서로 호출하면(`memberService()` 안에서 `memberRepository()` 호출) `new`가 여러 번 될 것 같지만, 실제론 **한 번만** 생성된다.
- 스프링이 `@Configuration` 클래스를 **CGLIB로 바이트코드 조작한 상속 프록시**로 만들어 빈으로 등록하기 때문.
- 이 프록시가 `@Bean` 호출을 가로채: **이미 등록된 빈이 있으면 반환, 없으면 생성** 후 등록 → 싱글톤 보장.
```
호출 → [CGLIB 프록시] → 컨테이너에 이 빈 있나?
                         ├─ 있음 → 기존 인스턴스 반환
                         └─ 없음 → new 해서 등록 후 반환
```
- **`@Configuration`을 빼면** CGLIB가 안 붙어서 이 보장이 사라진다 → `@Bean` 호출마다 `new` = 싱글톤 깨짐.

## 확인 문제
1. 싱글톤 빈을 쓸 때 절대 하면 안 되는 설계는?
2. `@Configuration`을 붙이면 스프링이 내부적으로 무엇을 하나?

<details><summary>답</summary>

1. **stateful 설계(공유 필드에 요청별 상태 저장)**. 다른 요청이 값을 덮어써 데이터가 꼬인다. 무상태로 설계하고, 값은 지역변수·파라미터·반환값으로 주고받는다.
2. `@Configuration` 클래스를 **CGLIB로 상속한 프록시 객체**를 만들어 빈으로 등록한다. 이 프록시가 `@Bean` 메서드 호출을 가로채 "이미 있으면 반환, 없으면 생성"으로 분기 → 빈의 싱글톤을 보장한다. 빼면 이 보장이 사라진다.

</details>

## 더 볼 것
- [[spring-02-container-and-bean]] — 컨테이너·빈 생성 과정
- [[spring-04-component-scan]] — 빈 자동 등록
- [[design-02-singleton]] — 싱글톤 패턴 자체
