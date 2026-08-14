# Spring Security JWT 필터체인과 403 에러 디스패치 함정

**한 문장**: 요청은 컨트롤러 도착 전에 보안 필터체인을 지나며, JWT 필터가 토큰을 검증해 "인증됨"을 `SecurityContext`에 세팅한다. 거절 여부는 뒤의 인가 단계가 결정하는데, 이 구조 때문에 400/404가 403으로 둔갑하는 함정이 있다.

## 왜 헷갈렸나
인증 필터·시큐리티 설정을 다 맞게 짰는데, 실제로 때려보니 **회원가입 잘못된 입력도, 유효 토큰으로 보호경로 접근도 전부 403**이 나왔다. "토큰이 유효한데 왜 막히지? 검증 실패는 400이어야 하는데 왜 403이지?"가 안 잡혔다. 범인은 인증 로직이 아니라 **에러가 `/error`로 다시 필터체인을 타는 흐름**이었다.

## 핵심

### 1. 필터체인 = 컨트롤러 앞의 문지기 줄
```
요청 → [필터1 → ... → JwtAuthenticationFilter → ... → AuthorizationFilter] → 컨트롤러
                          │                              │
              토큰 검증→SecurityContext에         SecurityContext 보고
              "인증됨" 도장                        통과/거절(401·403) 결정
```
- **인증(Authentication)**: "누구냐" — JWT 필터가 토큰 까서 userId를 SecurityContext에 넣음.
- **인가(Authorization)**: "권한 되냐" — 뒤의 `AuthorizationFilter`가 그 컨텍스트를 보고 판단.
- 둘은 **역할이 분리**돼 있다. 필터는 토큰이 틀려도 직접 거절하지 않고 "인증 안 넣고 통과", 거절은 인가가.

### 2. JWT 필터는 `OncePerRequestFilter`
```java
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain) {
        String header = req.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            try {
                Long userId = jwtProvider.parseUserId(header.substring(7)); // 검증+파싱, 실패시 예외
                var auth = new UsernamePasswordAuthenticationToken(userId, null, List.of());
                SecurityContextHolder.getContext().setAuthentication(auth); // "인증됨" 도장
            } catch (JwtException e) {
                // 유효하지 않은 토큰 → 인증 없이 통과 (거절은 인가 단계가)
            }
        }
        chain.doFilter(req, res); // ★ 반드시 다음으로 넘김
    }
}
```
- `OncePerRequestFilter` = 요청당 한 번만 실행 보장. **단, 기본적으로 에러 디스패치 땐 안 돈다** — 이게 아래 함정의 원인.

### 3. ⚠️ 함정: 400/404가 403으로 둔갑
스프링은 컨트롤러 처리 중 **에러(404·400 등)가 나면 내부적으로 `/error`로 재요청(forward)** 한다. 그런데:
```
GET /events (컨트롤러 없음) → 404 → /error 로 재요청(ERROR 디스패치)
                                       │
              AuthorizationFilter가 또 돎 + JWT필터는 에러 디스패치엔 안 돎(인증 비어있음)
              /error 는 permitAll 아님 → authenticated() → 막힘 → 403
```
- 그래서 **404든, 검증실패 400이든 전부 `/error`를 거치며 403으로 바뀐다.** 유효 토큰으로 접근해도 최종 응답이 404가 아니라 403이 되어 "인증이 안 먹나?"로 오해하게 된다.
- 또 하나: 인증 실패 시 스프링 기본 응답은 **401이 아니라 403**(`Http403ForbiddenEntryPoint`). 401을 원하면 진입점을 바꿔야 한다.

### 4. 해결 — SecurityConfig 2줄
```java
http.csrf(c -> c.disable())
    .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
    .authorizeHttpRequests(auth -> auth
            .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()          // ★① 에러 디스패치 통과
            .requestMatchers("/api/v1/health", "/api/v1/auth/**").permitAll()
            .anyRequest().authenticated())
    .exceptionHandling(ex -> ex.authenticationEntryPoint(                      // ★② 인증실패 → 401
            (req, res, e) -> res.sendError(HttpServletResponse.SC_UNAUTHORIZED)))
    .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
```
- **①** `/error` 디스패치를 인가 검사에서 통과 → 404는 404로, 검증실패는 400으로 제 코드가 나옴.
- **②** 인증 안 된 요청/인증 예외에 401을 주도록 진입점 교체.

## 예시 코드
Pulse에서 고친 뒤 실제 검증 결과:

| 요청 | 고치기 전 | 고친 후 |
|------|-----------|---------|
| signup 잘못된 바디 | 403 | **400** (검증 작동) |
| 보호경로 토큰 없이 | 403 | **401** |
| 보호경로 유효 토큰 | 403 | **404** (컨트롤러 없음 = 인증은 통과!) |
| 틀린 비번 로그인 | 403 | **401** |
| 조작된 토큰 | 403 | **401** (서명 검증) |

> "유효 토큰 → 404"가 뜨면 **인증은 통과했다(필터가 도장 찍었다)**는 증거. 403이면 인증 자체가 안 먹은 것.

## 확인 문제
1. 유효한 토큰으로 컨트롤러 없는 보호경로를 쳤더니 403이 나왔다. 인증이 실패한 걸까? 왜 그런 응답이 나오고 어떻게 고치나?
2. JWT 필터는 토큰이 틀려도 왜 직접 401/403을 던지지 않고 `catch`를 비운 채 통과시키나?

<details><summary>답</summary>

1. **인증 실패가 아닐 수 있다.** 컨트롤러가 없어 404가 나고, 그 404가 `/error`로 재요청되는데 그 에러 디스패치엔 인증정보가 없어(OncePerRequestFilter가 에러 디스패치엔 안 돎) `/error`가 `authenticated()`에 걸려 403이 된다. `.dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()`로 에러 디스패치를 통과시키면 원래 코드(404)가 그대로 나온다.
2. 인증(누구냐)과 인가(권한 되냐)의 **역할 분리** 때문. 필터가 토큰 틀렸다고 직접 거절하면 공개 엔드포인트조차 잘못된 토큰 하나로 막힌다. 그래서 필터는 "유효하면 도장, 아니면 그냥 통과"만 하고, 거절 여부는 뒤의 인가 단계에 위임한다.

</details>

## 더 볼 것
- [[spring-05-di-autowired]] — 필터·빈 주입
- [[jpa-lazy-loading]] — 같은 프로젝트(Pulse) 0-2
- 키워드: `SecurityFilterChain`, `AuthorizationFilter`, `ExceptionTranslationFilter`, stateless, `@PreAuthorize`

## 커스텀(非시큐리티) 필터를 시큐리티 앞/뒤에 두기 — @Order

`@Component extends OncePerRequestFilter`는 기본 order가 `LOWEST_PRECEDENCE`라 시큐리티 `FilterChainProxy`(order **-100**)보다 **뒤(안쪽)**에 등록된다. 그래서 시큐리티가 401/403으로 거부한 요청은 이 필터의 `chain.doFilter`까지 오지도 못한다 — 예: 액세스 로깅 필터가 인증실패 요청을 못 남긴다.

- 해결: `@Order(Ordered.HIGHEST_PRECEDENCE)`로 시큐리티보다 **먼저** 실행 → 시큐리티 체인을 `try/finally`로 감싸므로 거부된 요청도 `finally`에서 최종 status(401/403)까지 로깅.
- 규칙: **낮은 order = 먼저(바깥), 높은 order = 나중(안쪽).** 응답 status는 체인이 끝난 뒤라야 확정되므로 `finally`에서 읽는다.
