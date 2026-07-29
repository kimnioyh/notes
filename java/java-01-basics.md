# 자바 기본 개념 정리

> 스프링을 이해하는 데 필요한 자바 개념만 추려서 정리. 예시는 피드백 API 프로젝트 기준.

## 클래스와 객체

- **클래스**: 설계도. **객체**: 설계도로 찍어낸 실제 물건.

```java
public class Feedback {      // 설계도
    private String message;
}

Feedback f = new Feedback(); // 객체(인스턴스) 생성
```

## 접근 제어자

누가 이 필드/메서드에 접근할 수 있는지 정함.

| 제어자 | 접근 범위 |
|---|---|
| `public` | 어디서든 |
| `private` | 이 클래스 안에서만 |
| `protected` | 같은 패키지 + 자식 클래스 |
| (없음) | 같은 패키지 |

- 필드는 보통 `private`, 접근은 메서드(getter)로. → **캡슐화**

## 생성자

객체가 만들어질 때 실행되는 초기화 코드.

```java
public class Feedback {
    private String message;

    public Feedback(String message) {   // 생성자
        this.message = message;
    }
}
```

- 스프링의 **생성자 주입**이 이걸 이용함 (뒤 스프링 노트 참고).

## 인터페이스 vs 클래스

- **인터페이스**: "무엇을 할 수 있다"는 약속(메서드 목록)만 정의. 구현은 없음.
- **클래스**: 실제 구현.
- `implements` 로 인터페이스를 구현.

```java
public interface FeedbackRepository extends JpaRepository<Feedback, Long> { }
//         ↑ 인터페이스만 선언했는데, 스프링이 구현체를 자동으로 만들어줌
```

> 스프링 Data JPA가 인터페이스만 보고 구현을 자동 생성하는 게 이 개념 위에 서 있음.

## 제네릭 `<T>`

"어떤 타입인지"를 꺾쇠로 지정. 타입 안전성을 줌.

```java
List<Feedback> list;        // Feedback만 담는 리스트
Optional<Feedback> result;  // Feedback이 있을 수도/없을 수도
JpaRepository<Feedback, Long>  // 엔티티=Feedback, id 타입=Long
```

## record

값을 담기만 하는 클래스를 한 줄로. getter·생성자·equals 자동 생성. **DTO에 잘 맞음.**

```java
public record FeedbackRequest(String message) {}
// message() 게터, 생성자 등이 자동으로 생김

FeedbackRequest req = new FeedbackRequest("좋아요");
req.message();  // "좋아요"
```

## Optional

"값이 없을 수도 있음"을 타입으로 표현. `null` 대신 씀 → NPE 예방.

```java
Optional<Feedback> result = repository.findById(id);

// 껍데기 벗기는 법
Feedback f = result.orElseThrow(() -> new IllegalArgumentException("없음"));
// 또는 값 변환
FeedbackResponse dto = result
        .map(x -> new FeedbackResponse(x.getId(), x.getMessage()))
        .orElseThrow(...);
```

- `findById` 가 `Optional` 을 주는 이유: 그 id가 없을 수도 있어서. 강제로 "없는 경우"를 처리하게 만드는 안전장치.

## 람다 & 스트림

컬렉션을 함수형으로 처리. 서비스에서 엔티티 리스트 → DTO 리스트 변환할 때 씀.

```java
return repository.findAll().stream()               // 스트림 시작
        .map(f -> new FeedbackResponse(f.getId(), f.getMessage()))  // 각각 변환
        .toList();                                  // 리스트로 수집
```

- `f -> ...` 가 **람다**(짧은 익명 함수).
- `.map()` = 각 요소를 다른 값으로 바꿈, `.toList()` = 결과를 리스트로.

## 어노테이션

`@` 로 시작하는 표시. 코드에 "메타 정보"를 붙여서, 스프링 같은 프레임워크가 읽고 동작을 바꿈.

```java
@Service            // "이건 서비스다" → 스프링이 빈으로 등록
@GetMapping("/x")   // "이 주소 GET 요청을 이 메서드로"
```

- 어노테이션 자체는 아무 일도 안 함. **그걸 읽는 쪽(스프링)이 동작을 정함.**

## 예외 (Exception)

에러 상황을 객체로 표현하고 던짐(throw).

```java
throw new IllegalArgumentException("피드백 없음: " + id);
```

| 종류 | 설명 |
|---|---|
| Checked | 컴파일 때 처리 강제 (예: `IOException`) |
| Unchecked (`RuntimeException` 계열) | 강제 안 됨. 스프링 웹에선 주로 이걸 던지고 전역 핸들러가 처리 |

- 던진 예외를 컨트롤러마다 잡지 않고, `@RestControllerAdvice` 로 한 곳에서 처리 (스프링 노트 참고).

---

## 한눈에

| 개념 | 프로젝트에서 어디에 |
|---|---|
| 생성자 | 생성자 주입 (컨트롤러가 서비스 받기) |
| 인터페이스 | `FeedbackRepository` (구현 자동 생성) |
| 제네릭 | `List<>`, `Optional<>`, `JpaRepository<>` |
| record | DTO (`FeedbackRequest`, `FeedbackResponse`) |
| Optional | `findById` 결과 처리 |
| 람다/스트림 | 엔티티 → DTO 리스트 변환 |
| 어노테이션 | 스프링 전반 |
| 예외 | 검증 실패·조회 실패 처리 |

→ 다음: [스프링 개념 노트](spring-01-concepts.md)
