# Java enum에 필드·생성자 달기

**한 문장**: Java의 enum 상수는 Python처럼 단순 이름표가 아니라, **각자 데이터를 들고 다니는 객체**라서 생성자를 호출해 필드를 채울 수 있다.

## 왜 헷갈렸나
- 상수 옆 괄호 `EMAIL_ALREADY_EXISTS(HttpStatus.CONFLICT, "...")`가 뭔지, 생성자를 왜 만드는지 몰랐다.
- 어떤 상수는 인자를 안 넘겼더니(`UNAUTHORIZED()`) 컴파일이 안 됐다.

## 핵심
- enum 상수는 사실 **그 enum 타입의 인스턴스**다. 각 상수가 정의될 때 **생성자가 호출**된다.
- 상수 옆 괄호 = **생성자 호출**. 그래서 생성자 시그니처에 맞는 인자를 넘겨야 한다.
- 생성자는 항상 **private**(암묵적). 밖에서 `new`로 못 만든다.
- 상수 목록 **마지막 뒤에 세미콜론** 필수(상수 목록이 끝났다는 표시).
- 밖에서 필드를 읽으려면 **접근자(getter)**를 열어야 한다(필드는 보통 `private final`).

**함정**: 생성자를 2-인자로 만들었으면 **모든 상수가 2개를 넘겨야** 한다. `UNAUTHORIZED()`처럼 빈 괄호는 "인자 없는 생성자"를 찾는데, 그게 없으면 컴파일 에러.

## 예시 코드
프로젝트의 `ErrorCode` — "코드 ↔ HTTP상태 ↔ 기본메시지"를 한 표에 묶었다:
```java
public enum ErrorCode {
    EMAIL_ALREADY_EXISTS(HttpStatus.CONFLICT, "이미 가입된 이메일입니다"), // 409
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "인증이 필요합니다");            // 401
    // ↑ 마지막 상수 뒤 세미콜론 필수

    private final HttpStatus status;
    private final String defaultMessage;

    ErrorCode(HttpStatus status, String defaultMessage) { // private (암묵적)
        this.status = status;
        this.defaultMessage = defaultMessage;
    }
    public HttpStatus status() { return status; }          // 접근자 없으면 밖에서 못 읽음
    public String defaultMessage() { return defaultMessage; }
}
```
쓸 때: `ErrorCode.EMAIL_ALREADY_EXISTS.status()` → `409 CONFLICT`. "코드가 상태를 스스로 안다" → 핸들러가 분기 안 하고 물어보기만 하면 됨.

## 확인 문제
1. `MY_CODE(400, "msg")`에서 `400`은 정확히 무엇이 되나?
2. 생성자를 `(int, String)`로 만들었는데 상수 하나를 `FOO()`로 쓰면 왜 컴파일이 안 되나?

<details><summary>답</summary>

1. enum 생성자 `MyEnum(int, String)`을 호출하는 **인자**다. 상수 `MY_CODE`를 만들면서 그 생성자로 필드를 채운다.
2. 생성자가 `(int, String)` 하나뿐인데 `FOO()`는 **인자 없는 생성자**를 호출하려는 것 → 그런 생성자가 없어서 "no suitable constructor" 컴파일 에러. 모든 상수가 `(int, String)` 인자를 넘겨야 한다.

</details>

## 더 볼 것
- 실제 활용: [[spring-global-exception-handling]]의 에러 봉투
