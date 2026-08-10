# Spring MVC 컨트롤러 파라미터 바인딩 (@PathVariable · @AuthenticationPrincipal · @RequestBody)

**한 문장**: 컨트롤러 메서드 파라미터는 **값의 출처마다 다른 애너테이션**으로 뽑는다 — 경로는 `@PathVariable`, JSON 바디는 `@RequestBody`, **로그인 유저 id는 쿠키를 직접 읽는 게 아니라 `@AuthenticationPrincipal`**(JWT 필터가 SecurityContext에 넣어둔 값).

## 왜 헷갈렸나
세션 컨트롤러에서 유저 id를 `@CookieValue(name = "userId") Long userId`로 읽으려 했는데 안 됐다. **"userId"라는 쿠키는 없기 때문.** 유저 식별자는 JWT(accessToken 쿠키) **안에** 있고, 필터가 그걸 파싱해서 SecurityContext에 넣어둔다. 그걸 꺼내는 건 `@AuthenticationPrincipal`이다.

## 핵심

### 출처별 애너테이션
| 값 | 애너테이션 | 출처 |
|----|-----------|------|
| URL 경로 조각 | `@PathVariable String eventCode` | `/events/{eventCode}` |
| JSON 바디 | `@Valid @RequestBody SessionCreateRequest req` | 요청 body |
| **로그인 유저** | `@AuthenticationPrincipal Long userId` | **SecurityContext의 principal** |
| 특정 쿠키 값 | `@CookieValue("name") String v` | 쿠키(우리는 유저 id용으로 안 씀) |
| 쿼리스트링 | `@RequestParam Long sessionId` | `?sessionId=...` |

### 유저 id는 왜 @AuthenticationPrincipal인가 (흐름)
```
accessToken 쿠키(JWT)
   → JwtAuthenticationFilter가 쿠키에서 토큰 꺼내 파싱 → userId
   → new UsernamePasswordAuthenticationToken(userId, ...) 를 SecurityContextHolder에 저장
   → 컨트롤러의 @AuthenticationPrincipal Long userId 가 그 principal을 꺼냄
```
- `@CookieValue("userId")`는 **"userId"라는 이름의 쿠키를 직접** 찾는다 → 그런 쿠키가 없으니 실패. 토큰 전송방식(헤더/쿠키)이 바뀌어도 컨트롤러는 `@AuthenticationPrincipal`만 쓰면 그대로 동작(전송 무관).

### @PathVariable 이름 매칭
- 경로 변수명과 파라미터명이 같으면 자동 매칭: `/{eventCode}` ↔ `@PathVariable String eventCode`.
- 다르면 명시: `@PathVariable("eventCode") String code`.
- 중첩 경로는 여러 개: `/events/{eventCode}/sessions/{sessionId}` → `@PathVariable String eventCode, @PathVariable Long sessionId`.

## 예시 코드
Pulse `SessionController` — 경로 2개 + 인증 주체 + 바디:
```java
@PatchMapping("/{sessionId}")   // 클래스 @RequestMapping("/api/v1/events/{eventCode}/sessions")
public SessionResponse update(
        @AuthenticationPrincipal Long userId,          // JWT 쿠키 → 필터 → SecurityContext
        @PathVariable Long sessionId,                  // URL 경로
        @Valid @RequestBody SessionUpdateRequest req) { // JSON 바디
    return sessionService.update(req, userId, sessionId);
}
```
공개 목록은 인증 주체 없이 경로만: `getPublic(@PathVariable String eventCode)`.

## 확인 문제
1. 로그인한 유저의 id를 컨트롤러에서 꺼낼 때 `@CookieValue("userId")`가 안 되는 이유는? 뭘 써야 하나?
2. 인증 토큰을 헤더 → 쿠키로 바꿔도 컨트롤러 코드를 안 고쳐도 되는 이유는?

<details><summary>답</summary>

1. "userId"라는 쿠키가 존재하지 않는다. 유저 식별자는 accessToken 쿠키의 JWT 안에 들어있고, `JwtAuthenticationFilter`가 파싱해 SecurityContext의 principal로 넣어둔다. 그걸 꺼내는 건 `@AuthenticationPrincipal Long userId`.

2. 컨트롤러는 전송방식(헤더/쿠키)을 모르고 `@AuthenticationPrincipal`로 SecurityContext의 principal만 읽는다. 토큰을 어디서 꺼내 principal을 채울지는 필터의 몫이라, 전송을 바꿔도 필터만 고치면 되고 컨트롤러는 그대로다.

</details>

## 더 볼 것
- [[spring-security-jwt-filter-chain]] — 필터가 어떻게 SecurityContext를 채우는지
- [[cookie-based-auth]] — 토큰이 쿠키로 오는 경우의 전체 흐름
