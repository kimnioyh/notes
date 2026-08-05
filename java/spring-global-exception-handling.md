# Spring 전역 예외 처리 (@RestControllerAdvice)

**한 문장**: 예외가 나는 **위치(필터단 vs 컨트롤러단)**에 따라 잡는 놈이 다르고, 둘 다 손봐야 앱 전체 에러 응답을 `{code, message}` 한 봉투로 통일할 수 있다.

## 왜 헷갈렸나
- `@RestControllerAdvice`를 달았는데 401/403(인증/인가 실패)은 안 잡혔다. "전역"이라며 왜 어떤 건 못 잡지?
- 깨진 JSON을 보냈더니 400이 아니라 500이 났다.

## 핵심

**요청이 지나는 두 구역, 예외를 잡는 놈이 다르다:**
```
요청 → [시큐리티 필터체인] → DispatcherServlet → [컨트롤러 → 서비스]
        (JWT필터·인가체크)                          (비즈니스 로직)
   └── 구역 A ──┘                            └──── 구역 B ────┘
```
- **구역 B (컨트롤러/서비스 안)**: `@RestControllerAdvice` + `@ExceptionHandler`가 잡음. MVC 계층 담당.
- **구역 A (필터체인 안)**: 아직 컨트롤러 근처도 안 감 → **Advice가 못 잡음.** 시큐리티가 `authenticationEntryPoint`(401) / `accessDeniedHandler`(403)로 따로 처리.

**`@RestControllerAdvice`** = `@ControllerAdvice` + `@ResponseBody`. 모든 컨트롤러 가로질러 예외를 잡고, 반환값이 JSON 바디로 나감. `@ExceptionHandler(X.class)` 메서드가 터진 예외 타입에 매칭됨(가장 구체적인 타입 우선).

**핸들러 메서드 순서 주의 (구체 → 일반):**
- `HttpMessageNotReadableException` → 깨진 JSON. **`@Valid`보다 먼저** Jackson 역직렬화에서 터짐. 이걸 안 잡으면 `Exception` fallback으로 떨어져 **500**이 됨(클라 잘못인데). → 400으로 잡아야.
- `MethodArgumentNotValidException` → `@Valid` 검증 실패. 필드 에러는 `getFieldError()`(단수, 첫 개 or null) 또는 `getFieldErrors()`(복수, List라 `getDefaultMessage()` 없음 → stream 필요).
- `Exception` → 나머지 fallback(500). 내부 메시지는 노출 금지.

## 예시 코드
```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(ApiException.class) // 우리가 의도적으로 던진 도메인 예외
    public ResponseEntity<ErrorResponse> handleApiException(ApiException e) {
        ErrorCode code = e.errorCode();
        return ResponseEntity.status(code.status()).body(new ErrorResponse(code.name(), e.getMessage()));
    }
    @ExceptionHandler(HttpMessageNotReadableException.class) // 깨진 JSON → 400 (안 잡으면 500)
    public ResponseEntity<ErrorResponse> handleUnreadable(HttpMessageNotReadableException e) { ... }
    @ExceptionHandler(Exception.class) // fallback → 500
    public ResponseEntity<ErrorResponse> handleUnexpected(Exception e) { ... }
}
```
구역 A는 `SecurityConfig`에서 직접 봉투를 씀(ObjectMapper 없이 JSON 문자열 조립 — Boot 4는 Jackson 3라 옛 `com.fasterxml...ObjectMapper` 주입이 안 됨):
```java
.exceptionHandling(ex -> ex
    .authenticationEntryPoint((req, res, e) -> writeError(res, ErrorCode.UNAUTHORIZED)) // 401
    .accessDeniedHandler((req, res, e) -> writeError(res, ErrorCode.NOT_OWNER)))         // 403
```

## 확인 문제
1. `@RestControllerAdvice`가 왜 토큰 없는 401을 못 잡나? 그건 어디서 처리하나?
2. 깨진 JSON 바디가 500으로 새는 이유와 고치는 법은?

<details><summary>답</summary>

1. 401은 **필터체인(구역 A)**에서 발생 → 아직 DispatcherServlet/컨트롤러에 도달 전이라 MVC 예외처리인 Advice가 못 잡는다. `SecurityConfig`의 `authenticationEntryPoint`(401)/`accessDeniedHandler`(403)에서 처리한다.
2. `@Valid` 검증 **전에** Jackson이 역직렬화하다 `HttpMessageNotReadableException`을 던지는데, 이 핸들러가 없으면 `@ExceptionHandler(Exception.class)` fallback으로 떨어져 500이 된다. `@ExceptionHandler(HttpMessageNotReadableException.class)`를 추가해 400 `VALIDATION_ERROR`로 매핑하면 된다.

</details>

## 더 볼 것
- [[spring-security-jwt-filter-chain]] — 필터체인 구조
- 에러 코드 설계는 프로젝트의 `ErrorCode` enum + [[java-enum-with-fields]]
