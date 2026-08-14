# Spring Security 필터 순서와 커스텀 필터 등록

**한 문장**: `@Component`로 등록한 서블릿 필터는 기본적으로 Spring Security 체인 **뒤에** 놓여서, 시큐리티가 거부한(401/403) 요청은 그 필터를 못 본다 — `@Order(HIGHEST_PRECEDENCE)`로 앞에 두면 감싼다.

## 왜 헷갈렸나
요청/응답 로깅 필터를 만들었는데, **인증 실패(401)·인가 실패(403) 요청이 로그에 아예 안 찍혔다.** 정작 배포에서 제일 보고 싶은 게 그 에러들인데. "필터를 만들었는데 왜 어떤 요청은 통과를 안 하지?"

## 핵심
- Spring Boot에서 필터는 두 갈래로 실행된다:
  - **서블릿 필터 체인** (톰캣 레벨). `@Component extends OncePerRequestFilter`는 여기에 등록.
  - 그 안의 한 칸이 Spring Security의 **`FilterChainProxy`** (order **-100**).
- `@Component` 필터는 기본 order가 `LOWEST_PRECEDENCE`(=`Integer.MAX_VALUE`) → **시큐리티보다 뒤**(안쪽)에 등록된다.
- 시큐리티가 요청을 거부하면(`authenticationEntryPoint`/`accessDeniedHandler`가 응답을 직접 쓰고 체인을 끊음), **뒤에 있는 내 필터의 `chain.doFilter`가 아예 호출되지 않는다.** → 로그 안 남음.
- **해결**: 필터를 `@Order(Ordered.HIGHEST_PRECEDENCE)`로 등록 → order `Integer.MIN_VALUE` < -100이라 **시큐리티보다 먼저** 실행. 시큐리티 체인 전체를 `try/finally`로 감싸므로, 거부된 요청도 `finally`까지 돌아와 최종 status(401/403)가 찍힌다.
- 낮은 order = 먼저 실행(바깥). 높은 order = 나중(안쪽).

## 예시 코드
```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)   // 시큐리티(-100)보다 앞 → 거부된 요청도 감쌈
public class RequestLoggingFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        long start = System.nanoTime();
        try {
            chain.doFilter(req, res);
        } finally {
            long ms = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
            // res.getStatus()는 체인이 끝난 뒤라 시큐리티가 확정한 최종 값(401/403 포함)
            log.info("[RES] {} {} -> {} ({}ms)", req.getMethod(), req.getRequestURI(), res.getStatus(), ms);
        }
    }
}
```

## 확인 문제
1. `@Order` 없이 그냥 `@Component`만 붙이면 로깅 필터가 시큐리티 앞이야 뒤야? 그 결과는?
2. `res.getStatus()`를 `finally`에서 읽는 게 왜 중요한가?

<details><summary>답</summary>

1. **뒤(안쪽)**. 기본 order가 `LOWEST_PRECEDENCE`라 시큐리티(-100)보다 뒤. 그래서 시큐리티가 401/403으로 끊은 요청은 필터까지 도달을 못 해 로그가 안 남는다. `@Order(HIGHEST_PRECEDENCE)`로 앞에 두면 감싸서 다 찍힌다.
2. status는 컨트롤러·시큐리티가 응답을 **확정한 뒤**에야 정해진다. 요청 진입 시점엔 알 수 없다. `finally`(체인 실행 후)에서 읽어야 시큐리티가 쓴 401/403이나 핸들러가 정한 최종 코드가 잡힌다.

</details>

## 더 볼 것
- `SecurityProperties.DEFAULT_FILTER_ORDER = -100` (FilterChainProxy 등록 order)
- [[cors-preflight]] — CORS 필터도 이 체인 순서에 얽혀 있음
