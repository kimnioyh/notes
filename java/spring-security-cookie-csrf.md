# Spring Security 6 — 쿠키 인증 + CSRF double-submit 설정

**한 문장**: 인증을 쿠키로 하면 CSRF가 필요한데, Spring Security 6에서 SPA용 double-submit은 `CookieCsrfTokenRepository` + 커스텀 `SpaCsrfTokenRequestHandler` + `CsrfCookieFilter` 3종 세트로 짜야 하고, 안 그러면 지연 토큰 때문에 XSRF-TOKEN 쿠키가 아예 안 나가는 함정이 있다.

## 왜 헷갈렸나
`csrf.disable()`로 꺼놨던 걸 다시 켜는데, 그냥 `CookieCsrfTokenRepository`만 붙이면 될 줄 알았다. 근데 Spring Security 6은 CSRF 토큰을 **지연 로드(deferred)**해서, 아무도 토큰을 건드리지 않으면 쿠키가 응답에 안 실린다. 게다가 BREACH 방어용 XOR 마스킹 때문에 SPA가 쿠키 raw값을 헤더로 보내면 검증이 어긋난다.

## 핵심

### 1. 저장소: CookieCsrfTokenRepository (stateless 호환)
```java
CookieCsrfTokenRepository repo = CookieCsrfTokenRepository.withHttpOnlyFalse(); // JS가 읽게
repo.setCookieCustomizer(c -> c.sameSite("None").secure(true)); // 환경별로
```
- `withHttpOnlyFalse()` = XSRF-TOKEN 쿠키를 **비-HttpOnly**로 → FE JS가 읽어 헤더로 되돌려보냄.
- 토큰이 쿠키에 저장되므로 `SessionCreationPolicy.STATELESS`와도 호환(서버 세션 불필요).

### 2. SpaCsrfTokenRequestHandler — 렌더는 XOR, 검증은 평문
```java
final class SpaCsrfTokenRequestHandler implements CsrfTokenRequestHandler {
    private final CsrfTokenRequestHandler plain = new CsrfTokenRequestAttributeHandler();
    private final CsrfTokenRequestHandler xor = new XorCsrfTokenRequestAttributeHandler();
    public void handle(req, res, csrfToken) { xor.handle(req, res, csrfToken); csrfToken.get(); }
    public String resolveCsrfTokenValue(req, csrfToken) {
        // 헤더로 오면 평문(SPA가 쿠키 raw값 그대로), 폼이면 XOR
        return (StringUtils.hasText(req.getHeader(csrfToken.getHeaderName())) ? plain : xor)
            .resolveCsrfTokenValue(req, csrfToken);
    }
}
```

### 3. CsrfCookieFilter — 지연 토큰을 강제 렌더 (이게 핵심 함정)
```java
final class CsrfCookieFilter extends OncePerRequestFilter {
    protected void doFilterInternal(req, res, chain) {
        CsrfToken t = (CsrfToken) req.getAttribute("_csrf");
        if (t != null) t.getToken();   // 건드려야 쿠키에 실린다
        chain.doFilter(req, res);
    }
}
```
안 건드리면 지연 로드라 XSRF-TOKEN 쿠키가 응답에 안 나감 → FE가 토큰을 못 받음.

### 4. 조립 + login/signup은 CSRF 예외
```java
http.csrf(csrf -> csrf
        .csrfTokenRepository(repo)
        .csrfTokenRequestHandler(new SpaCsrfTokenRequestHandler())
        .ignoringRequestMatchers("/api/v1/auth/login", "/api/v1/auth/signup")) // 토큰 없는 진입점
    .addFilterAfter(new CsrfCookieFilter(), BasicAuthenticationFilter.class);
```
- login/signup은 아직 토큰이 없는 진입점이라 예외(login CSRF는 저위험).
- **CSRF 실패는 `AccessDeniedException`(정확히는 `CsrfException`)** → `accessDeniedHandler`에서 `NOT_OWNER` 대신 전용 코드로 분기해야 원인이 안 헷갈린다.

## 예시 코드
Pulse `SecurityConfig` — 위 3종 + CORS `allowCredentials(true)` + 쿠키 Secure/SameSite를 환경별 프로퍼티로. 로컬 실측: `/health`가 `Set-Cookie: XSRF-TOKEN=...; SameSite=Lax` 내려주고, 인증 쿠키만 있고 X-XSRF-TOKEN 없이 POST하면 403(CSRF 차단) 확인.

## 확인 문제
1. `CookieCsrfTokenRepository`만 붙였는데 XSRF-TOKEN 쿠키가 응답에 안 나온다. 왜? 어떻게 고치나?
2. login/signup을 `ignoringRequestMatchers`로 CSRF 예외 두는 이유는?

<details><summary>답</summary>

1. Spring Security 6은 CSRF 토큰을 지연 로드해서, 아무도 `csrfToken.getToken()`을 호출하지 않으면 쿠키가 안 실린다. 매 요청 토큰을 강제로 건드리는 `CsrfCookieFilter`를 `BasicAuthenticationFilter` 뒤에 추가해 렌더시킨다.

2. 로그인·회원가입은 아직 클라이언트에 CSRF 토큰이 없는 최초 진입점이라, 그걸 CSRF 검증하면 아무도 로그인할 수 없다(닭-달걀). 그래서 예외로 두고, 응답에서 XSRF-TOKEN 쿠키를 내려 이후 요청부터 토큰을 갖게 한다.

</details>

## 더 볼 것
- [[cookie-based-auth]] — 왜 double-submit이 필요하고 cross-domain에서 깨지는지
- [[spring-security-jwt-filter-chain]] — 필터 체인 순서와 인증 필터 배치
