# CORS (교차 출처 요청) — preflight·허용목록·와일드카드 위험

**한 문장**: CORS는 브라우저가 "다른 출처(origin)의 API를 이 페이지가 읽어도 되나"를 서버에 물어보는 규칙이고, 허용 origin을 와일드카드로 열면 아무 사이트나 우리 응답을 읽는 보안 구멍이 된다.

## 왜 헷갈렸나
- Spring Security에서 CORS를 어떻게 켜는지, `allowedOriginPatterns`/`allowCredentials`가 뭔지 잘 몰랐다.
- CodeRabbit이 `https://*.vercel.app`를 Major 보안 이슈(CWE-942)로 잡았는데 왜 위험한지.

## 핵심
- **origin** = 스킴+호스트+포트 (`https://app.example.com:443`). 다르면 "교차 출처".
- **preflight**: 브라우저가 본 요청 전에 `OPTIONS`로 "이 메서드·헤더 써도 돼?"를 미리 물음. 서버가 `Access-Control-Allow-*` 헤더로 답. 그래서 CORS 허용 메서드에 `OPTIONS` 필수.
- Spring: `http.cors(...)` + `CorsConfigurationSource` 빈. `http.cors()`가 없으면 빈만 있어도 적용 안 됨.
- `setAllowedOrigins` = 정확 매칭만. `setAllowedOriginPatterns` = `*` 와일드카드 허용(예: `http://localhost:*`).
- `allowCredentials(true)`면 쿠키/인증정보를 교차 출처로 주고받음. 이때 origin에 `*` 못 씀. **JWT를 헤더/바디로 쓰고 쿠키 안 쓰면 `false`**.

**와일드카드 위험 (CWE-942)**: `https://*.vercel.app`는 **누구나** Vercel에 올린 페이지를 허용 origin으로 만든다. `allowCredentials(false)`여도 못 막는 이유 — **토큰이 쿠키가 아니라 응답 바디**에 있어서, 허용 origin인 악성 페이지가 그냥 응답을 읽을 수 있음. → **정확한 도메인**이나 **환경변수 허용목록**으로 좁혀야.

## 예시 코드
안전한 버전 — origin을 프로퍼티/env로 주입, 와일드카드 제거:
```java
@Bean
CorsConfigurationSource corsConfigurationSource(
        @Value("${cors.allowed-origins}") List<String> allowedOrigins) {
    CorsConfiguration c = new CorsConfiguration();
    c.setAllowedOriginPatterns(allowedOrigins);              // 로컬 기본 http://localhost:*, 배포는 정확 도메인
    c.setAllowedMethods(List.of("GET","POST","PATCH","DELETE","OPTIONS")); // OPTIONS=preflight
    c.setAllowedHeaders(List.of("*"));
    c.setAllowCredentials(false);                            // JWT 헤더/바디, 쿠키 안 씀
    var src = new UrlBasedCorsConfigurationSource();
    src.registerCorsConfiguration("/**", c);
    return src;
}
```
```properties
# 배포는 env CORS_ALLOWED_ORIGINS로 실제 도메인 주입 (와일드카드 금지)
cors.allowed-origins=${CORS_ALLOWED_ORIGINS:http://localhost:*}
```
검증: `Origin: https://evil.vercel.app`로 preflight → `403`, `Access-Control-Allow-Origin` 헤더 없음(거부됨).

## 확인 문제
1. `allowCredentials(false)`인데도 `*.vercel.app` 와일드카드가 왜 위험한가?
2. `http.cors(Customizer.withDefaults())` 한 줄을 빼면 `CorsConfigurationSource` 빈이 있어도 어떻게 되나?

<details><summary>답</summary>

1. 토큰이 **쿠키가 아니라 응답 바디**에 담기기 때문. credentials(쿠키)와 무관하게, 허용 origin이면 그 페이지의 JS가 응답 바디를 읽을 수 있다. 와일드카드는 "아무 vercel.app 페이지나 허용"이라 임의의 악성 사이트가 우리 인증 응답을 읽게 된다(CWE-942).
2. CORS 필터가 그 빈을 안 씀 → CORS 설정이 적용되지 않는다. `http.cors()`가 "CorsConfigurationSource 빈을 찾아 쓰라"고 연결해주는 스위치다.

</details>

## 더 볼 것
- [[spring-security-jwt-filter-chain]]
