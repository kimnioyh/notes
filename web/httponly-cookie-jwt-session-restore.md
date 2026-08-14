# HttpOnly 쿠키 JWT와 /auth/me 세션 복원

**한 문장**: JWT를 HttpOnly 쿠키로 두면 XSS로 토큰을 못 훔치지만, FE도 토큰을 못 읽어서 로그인 상태를 알려면 `/auth/me`를 따로 호출해야 한다.

## 왜 헷갈렸나
로컬 로그에 `GET /api/v1/auth/me`가 유난히 많이, 그것도 같은 시각에 쌍으로 찍혔다. 로그아웃 뒤엔 `/auth/me -> 401`이 반복. "이거 백엔드가 뭔가 잘못 도는 거 아냐?" 싶었지만 전부 **정상 동작 + FE 패턴**이었다.

## 핵심
- **왜 HttpOnly 쿠키인가**: `localStorage`에 토큰을 두면 XSS 스크립트가 읽어 탈취 가능. HttpOnly 쿠키는 JS가 못 읽어(`document.cookie`에 안 보임) 그 벡터를 막는다. 브라우저가 요청에 자동 첨부.
- **대가**: FE가 토큰을 못 읽으니 "지금 로그인 상태인가?"를 스스로 판단 못 한다. → 서버에 물어봐야 함 = **`GET /auth/me`**. 쿠키가 유효하면 유저정보(200), 없으면/만료면 401.
- **그래서 /auth/me가 자주 뜬다**: 앱 마운트·라우트 이동·새로고침마다 세션 복원용으로 호출. 로그아웃(쿠키 삭제) 후의 `/auth/me -> 401`은 **맞는 동작**(FE가 "이제 비로그인" 확인).
- **같은 시각 쌍으로 찍히는 이유**: React **StrictMode(개발 모드)**가 effect를 의도적으로 두 번 실행한다. → `/auth/me`도 두 번. 프로덕션 빌드에선 안 겹친다.
- 이 쿠키는 cross-site(FE↔BE 다른 오리진)라 `SameSite=None; Secure` + CSRF double-submit 토큰과 함께 쓴다.

## 예시 코드
```java
// 발급: 로그인/가입 응답에 HttpOnly 쿠키로. 바디엔 토큰 없음(유저정보만)
ResponseCookie.from("accessToken", jwt)
    .httpOnly(true).secure(cookieSecure).sameSite(sameSite).path("/")
    .maxAge(Duration.ofSeconds(expires)).build();

// 복원용 엔드포인트: FE가 토큰을 못 읽으니 로그인 여부를 여기로 확인
@GetMapping("/me")
public AuthUser me(@AuthenticationPrincipal Long userId) {
    return authService.getUser(userId);   // 쿠키 무효면 시큐리티가 먼저 401
}
```
```js
// FE: 쿠키 자동 첨부 위해 credentials 포함 (이게 CORS 프리플라이트도 유발)
fetch('/api/v1/auth/me', { credentials: 'include' })
```

## 확인 문제
1. 왜 토큰을 응답 바디(JSON)로 주지 않고 굳이 쿠키로 주나?
2. 로그아웃했는데 `/auth/me`가 401을 주는 게 버그일까?

<details><summary>답</summary>

1. 바디로 주면 FE가 `localStorage` 등에 저장하게 되고, 그건 XSS로 탈취 가능한 자리다. HttpOnly 쿠키로 주면 JS가 접근 못 해 XSS 토큰 탈취를 원천 차단한다. 대신 FE가 토큰을 못 읽는 대가로 `/auth/me` 같은 상태 확인 엔드포인트가 필요해진다.
2. 버그 아님. 로그아웃이 쿠키를 만료시켰으니 이후 `/auth/me`는 인증이 없어 401이 **맞다.** FE는 이 401을 "비로그인"으로 해석해 로그인 화면으로 보낸다.

</details>

## 더 볼 것
- [[cors-preflight]] — credentials:'include'가 프리플라이트를 부르는 이유
- CSRF double-submit 토큰 (XSRF-TOKEN 쿠키 ↔ X-XSRF-TOKEN 헤더)
