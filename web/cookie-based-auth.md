# 쿠키 기반 JWT 인증 (HttpOnly · SameSite · 크로스도메인 CSRF)

**한 문장**: JWT를 localStorage 대신 **HttpOnly 쿠키**에 두면 XSS 토큰탈취는 막지만, 그 대가로 (1)FE가 토큰을 못 읽고 (2)쿠키가 자동 전송돼 CSRF 위험이 생기며 (3)FE·BE 도메인이 다르면 SameSite·쿠키읽기 문제가 줄줄이 딸려온다.

## 왜 헷갈렸나
"localStorage 방식이 야매 같다"며 쿠키로 옮기려는데, 쿠키 하나 바꾸는 게 아니라 **HttpOnly ↔ 유저정보 전달, SameSite ↔ CSRF, cross-domain ↔ 쿠키읽기**가 전부 얽혀 있었다. 특히 로컬(localhost)에선 잘 되는데 배포(Vercel↔Render)에선 깨지는 함정.

## 핵심

### 1. HttpOnly = JS가 토큰을 못 읽는다 (그게 목적)
- `document.cookie`로도 안 보이고 JS가 접근 불가 → XSS가 나도 토큰을 못 훔침(localStorage의 약점 해결).
- **부작용**: FE가 "내가 누구로 로그인했는지"를 토큰에서 못 꺼냄. 그래서
  - 로그인·회원가입 **응답 바디에 유저정보**(`{id,email,createdAt}`)를 줘야 하고,
  - 새로고침 복원용 **`GET /auth/me`**가 필요하다(HttpOnly라 그때 읽을 게 없으니).

### 2. SameSite: 쿠키를 cross-site 요청에 딸려보낼지
| 값 | 언제 전송 | CSRF 방어 |
|----|-----------|----------|
| Strict | 같은 사이트만 (링크 클릭도 X) | 최강, UX 불편 |
| Lax (기본) | 같은 사이트 + cross-site top-level GET(링크). cross-site POST/fetch는 X | 좋음 |
| None | 전부(cross-site fetch·POST 포함) | **없음**, `Secure` 필수 |

"사이트"는 등록도메인 기준(포트·서브도메인 무관): `localhost:3000`↔`:8080`=같은 사이트, `vercel.app`↔`render.com`=cross-site.

### 3. cross-site면 None 강제 → CSRF를 따로 막아야
FE·BE가 다른 사이트면 fetch가 cross-site라 Lax/Strict면 **쿠키가 아예 안 감** → `SameSite=None` 필수. 근데 None은 CSRF 방어가 0 → **double-submit 토큰**으로 막는다:
- 서버가 `XSRF-TOKEN` 쿠키(비-HttpOnly, JS가 읽음)를 내려주고,
- FE가 그 값을 `X-XSRF-TOKEN` 헤더로 되돌려보내면,
- 서버가 헤더 vs 쿠키를 비교. (공격사이트는 남의 도메인 쿠키를 못 읽어 헤더를 못 채움 + 커스텀헤더는 CORS preflight로 막힘)

### 4. ⚠️ 크로스도메인 double-submit의 함정 (놓치기 쉬운 크리티컬)
double-submit은 **FE JS가 `XSRF-TOKEN` 쿠키를 읽어야** 성립한다. 근데 쿠키는 **도메인 단위**라, BE(Render)가 심은 쿠키는 **FE(Vercel) 페이지의 `document.cookie`에 안 보인다**. → FE가 토큰을 못 읽어 헤더를 못 채움 → **배포되면 모든 인증 상태변경 요청이 CSRF 실패.**
- **왜 로컬은 통과?** `localhost:8080`↔`:3000`은 호스트가 같아(포트 무관) JS가 쿠키를 읽을 수 있음. 그래서 로컬 curl 테스트로는 절대 못 잡는다.
- **해법 A (권장): Vercel 프록시로 same-origin.** `app.vercel.app/api/*` → render 프록시하면 브라우저가 전부 Vercel origin으로 인식 → 쿠키가 Vercel 도메인에 심겨 JS가 읽음 → double-submit 동작. 게다가 CORS 불필요 + `SameSite=Lax`로 내려도 됨(더 안전).
- **해법 B: CSRF 부트스트랩 엔드포인트.** `GET /csrf`가 토큰을 **응답 바디**로 줌 → FE가 쿠키 대신 바디에서 읽어 헤더로 전송.

### 5. Secure + 환경별 설정 (fail-closed)
- `SameSite=None`은 `Secure=true`(HTTPS) 필수 — 브라우저가 None+비Secure를 거부.
- 로컬(http, same-site): `Lax`·`Secure=false`. 배포(https, 프록시 same-origin): `Lax`·`Secure=true`. cross-site 직결이면 `None`·`Secure=true`.
- 이 조합을 env/프로퍼티로 빼되, `None+비Secure` 같은 위험 조합은 **부팅 시 검증으로 막는다(fail-closed)**.

## 예시 코드
Pulse: FE Vercel ↔ BE Render(cross-site). 쿠키 인증 전환 후 로컬 curl은 다 통과했지만 CodeRabbit이 4번(크로스도메인 쿠키읽기)을 잡음 → 팀이 **Vercel 프록시(same-origin)**로 결정 → `SameSite=Lax`로 내리고 CSRF·CORS 복잡도 제거.

```
로그인:  POST /auth/login → Set-Cookie: accessToken=<jwt>; HttpOnly; Secure; SameSite=Lax
                          + 바디 { id, email, createdAt }   // HttpOnly라 바디로 신원 전달
이후:    fetch(..., { credentials: 'include' }) → 브라우저가 쿠키 자동 첨부
상태변경: XSRF-TOKEN 쿠키값을 X-XSRF-TOKEN 헤더로 (proxy면 same-origin이라 JS가 쿠키 읽음)
```

## 확인 문제
1. HttpOnly 쿠키로 토큰을 넣으면 왜 로그인 응답 바디에 유저정보를 줘야 하나?
2. FE(vercel)·BE(render)가 다른 도메인일 때 double-submit CSRF가 깨지는 이유는? 프록시가 왜 해결하나?
3. 로컬에서 잘 되는데 배포에서 CSRF가 깨진다면 가장 먼저 의심할 것은?

<details><summary>답</summary>

1. HttpOnly라 JS가 토큰을 못 읽어 "내가 누구인지"를 토큰에서 못 꺼낸다. 그 신원을 받을 유일한 즉시 통로가 응답 바디(+새로고침용 `/auth/me`)다.

2. double-submit은 FE JS가 `XSRF-TOKEN` 쿠키를 읽어 헤더로 보내야 하는데, 쿠키는 도메인 단위라 BE(render) 도메인 쿠키가 FE(vercel) 페이지 `document.cookie`에 안 보인다 → 토큰을 못 채워 CSRF 실패. 프록시로 `vercel.app/api/*`→render를 만들면 브라우저가 same-origin으로 보고 쿠키가 vercel 도메인에 심겨 JS가 읽을 수 있게 된다.

3. 도메인 차이(cross-site) 문제. 로컬은 localhost 한 호스트라 쿠키를 공유·읽을 수 있어 문제가 안 드러난다. SameSite/쿠키 도메인/CSRF 토큰 전달 경로를 의심.

</details>

## 더 볼 것
- [[cors-explained]] — credentials 허용과 정확한 origin 반사
- [[nextjs-vs-node-fetch]] — SSR에서 인증 쿠키를 수동 포워딩해야 하는 이유
- [[spring-security-cookie-csrf]] — Spring에서 이 double-submit을 실제 설정하는 법

## /auth/me가 로그에 많은 이유 (+ React StrictMode)

HttpOnly라 FE가 토큰을 못 읽으니, 마운트·라우트 이동·새로고침마다 `/auth/me`로 로그인 상태를 확인한다 → 로그에 자주 뜨는 게 **정상**. 로그아웃 뒤의 `/auth/me -> 401`도 맞는 동작(쿠키가 삭제됨).

- 같은 시각에 **쌍으로** 찍히면 React **StrictMode(dev)**가 effect를 두 번 실행해서다. 프로덕션 빌드에선 안 겹친다.
- 빈도 자체를 줄이려면 FE에서 react-query `staleTime`/캐시로 dedupe (백엔드 몫 아님).
