# Java 접근제어자 (public / protected / (없음) / private)

**한 문장**: 접근제어자 4단계는 "누가 이 멤버에 접근할 수 있나"를 정하며, **아무것도 안 붙이면(package-private) 같은 패키지에서만** 접근 가능하다.

## 왜 헷갈렸나
- `ApiException`의 생성자에 아무 제어자도 안 붙였더니, **다른 패키지**의 `AuthService`에서 `new ApiException(...)` 할 때 컴파일 에러가 났다. 클래스는 `public`인데 왜?

## 핵심
넓은 → 좁은 순:

| 제어자 | 접근 범위 |
|---|---|
| `public` | 아무나(다른 패키지 포함) |
| `protected` | 같은 패키지 + (다른 패키지의) 자식 클래스 |
| **(없음)** = package-private | **같은 패키지만** |
| `private` | 같은 클래스만 |

**핵심 함정**: 클래스를 `public`으로 열어도, **생성자를 안 열면(package-private)** 다른 패키지에서 `new` 못 한다. 클래스 접근성과 멤버(생성자/메서드) 접근성은 **따로** 판단된다.

## 예시 코드
```java
// com.hancome.pulse.common
public class ApiException extends RuntimeException {
    ApiException(ErrorCode c) { ... }   // ❌ 제어자 없음 = package-private
    // → com.hancome.pulse.auth 의 AuthService에서 new ApiException(...) 불가 (다른 패키지)
}
```
고침:
```java
    public ApiException(ErrorCode c) { ... }  // ✅ 다른 패키지에서도 생성 가능
```
반대로, 정말 같은 패키지에서만 만들게 하고 싶으면 일부러 package-private로 둔다(캡슐화). 즉 "실수로 안 붙인 것"과 "의도적으로 좁힌 것"을 구분해야 한다.

## 확인 문제
1. `public class Foo`인데 `Foo(int x) {}` 생성자에 제어자를 안 붙였다. 다른 패키지에서 `new Foo(1)`이 될까?
2. package-private과 `private`의 차이 한 문장으로.

<details><summary>답</summary>

1. 안 된다. 클래스는 public이라 **참조**는 가능하지만, 생성자가 **package-private**이라 다른 패키지에서 **생성(new)**은 불가. `public Foo(int x)`로 열어야 한다.
2. package-private(제어자 없음)은 **같은 패키지의 다른 클래스**도 접근 가능, `private`은 **오직 같은 클래스** 안에서만 접근 가능.

</details>
