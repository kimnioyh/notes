# CORS 프리플라이트 (preflight)

**한 문장**: 브라우저가 cross-origin으로 "단순하지 않은" 요청을 보내기 전에, 서버에 "이거 보내도 돼?"라고 먼저 묻는 자동 `OPTIONS` 요청.

## 왜 헷갈렸나
Pulse 로컬 로그에 `OPTIONS /api/v1/auth/login -> 200` 같은 줄이 실제 요청 앞마다 쌍으로 찍혀서 "이게 뭐지, 내 코드가 보낸 것도 아닌데" 싶었다. FE 코드에 `fetch('OPTIONS ...')` 같은 건 없는데 로그엔 계속 뜬다.

## 핵심
- **누가 보내나**: 브라우저가 **자동으로**. FE/BE 코드가 짜서 보내는 게 아니다.
- **언제 뜨나**: 요청이 cross-origin(FE `localhost:3000` ↔ BE `localhost:8080`, 또는 Vercel↔Render)이고 **"단순 요청(simple request)"이 아닐 때**. 하나라도 걸리면 프리플라이트:
  - 메서드가 `PATCH`·`DELETE`·`PUT`
  - 커스텀 헤더가 있음 (Pulse는 `X-XSRF-TOKEN`, `X-Client-Id`)
  - `Content-Type: application/json` (단순 폼 타입이 아님)
  - 자격증명 동반 (`credentials:'include'`로 쿠키 전송)
- **흐름**: ① 브라우저 → `OPTIONS`(사전 확인) → ② 서버가 `Access-Control-Allow-*` 헤더로 응답 → ③ 그제서야 진짜 요청.
- 서버는 Spring Security CORS 설정이 프리플라이트에 자동 응답한다(`200`).
- 앱 트래픽이 아니라 브라우저 뒷정리라, 로그가 요청당 두 배가 된다 → Pulse에선 로깅 필터 `shouldNotFilter`로 `OPTIONS`를 스킵했다.

## 예시 코드
```java
// RequestLoggingFilter: OPTIONS(프리플라이트)와 헬스체크는 액세스 로그에서 제외
@Override
protected boolean shouldNotFilter(HttpServletRequest req) {
    return "/api/v1/health".equals(req.getRequestURI())
        || "OPTIONS".equalsIgnoreCase(req.getMethod());
}
```
CORS 허용 자체는 SecurityConfig에서:
```java
config.setAllowedMethods(List.of("GET","POST","PATCH","DELETE","OPTIONS"));
config.setAllowedHeaders(List.of("*"));   // X-XSRF-TOKEN, X-Client-Id 등
config.setAllowCredentials(true);          // 쿠키 동반 → 프리플라이트 유발 조건
```

## 확인 문제
1. 같은 오리진(FE와 BE가 같은 도메인:포트)이면 프리플라이트가 뜰까?
2. `GET` 요청인데도 프리플라이트가 뜨는 경우는?

<details><summary>답</summary>

1. 안 뜬다. 프리플라이트는 **cross-origin**일 때만. same-origin이면 브라우저가 바로 진짜 요청을 보낸다. (그래서 FE를 BE와 같은 오리진에 두거나 프록시로 우회하면 프리플라이트가 사라짐.)
2. `GET`이라도 커스텀 헤더(`X-XSRF-TOKEN` 등)를 붙이거나 `credentials:'include'`로 쿠키를 보내면 "단순 요청" 조건을 벗어나 프리플라이트가 뜬다. 메서드만으로 결정되는 게 아니다.

</details>

## 더 볼 것
- `Access-Control-Max-Age` 헤더로 프리플라이트 결과를 캐시해 반복 OPTIONS를 줄일 수 있음
- [[httponly-cookie-jwt-session-restore]] — credentials:'include'가 프리플라이트를 유발하는 맥락
