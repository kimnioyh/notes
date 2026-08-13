# 프록시로 same-origin 만들기 (CORS·CSRF 동시 해결)

**한 문장**: FE에서 BE를 rewrites 프록시로 감싸 브라우저가 **같은 origin으로만 통신하게** 만들면, cross-origin이 아니게 되어 **CORS가 아예 발생하지 않고**, BE가 내린 `XSRF-TOKEN` 쿠키를 FE가 읽을 수 있게 되어 **CSRF double-submit도 동작**한다.

## 왜 헷갈렸나
FE(Vercel)와 BE(Render)가 다른 도메인이라 (1) CORS를 열어야 하고 (2) 쿠키 인증의 CSRF double-submit이 깨졌다(FE가 BE 도메인의 `XSRF-TOKEN` 쿠키를 `document.cookie`로 못 읽음). "프록시 하나로 둘 다 풀린다는데 어떻게?"가 안 잡혔다.

## 핵심

### 1. 프록시 = 브라우저가 자기 origin으로만 보게 하기
```js
// next.config.js (또는 vercel.json rewrites)
async rewrites() {
  return [{ source: '/api/:path*', destination: 'https://<app>.onrender.com/api/:path*' }];
}
```
```
브라우저 → https://myapp.vercel.app/api/... (same-origin)
Vercel   → https://app.onrender.com/api/...  (서버간 전달, 브라우저는 모름)
```
FE는 **상대경로 `/api/v1/...`로만** 호출해야 한다. 절대 URL로 `onrender.com`을 직접 치면 프록시를 안 타고 cross-site가 돼 도로 깨진다.

### 2. CORS는 same-origin이라 "발생 안 함"
브라우저가 자기 origin으로만 요청하니 cross-origin이 아니다 → **프리플라이트도 CORS 헤더도 불필요**. 즉 `CORS_ALLOWED_ORIGINS` 설정을 안 해도 된다. (Vercel→Render는 서버간이라 CORS 무관)

### 3. CSRF double-submit이 동작하는 이유
double-submit은 "BE가 내린 `XSRF-TOKEN` 쿠키 값을 FE JS가 읽어 `X-XSRF-TOKEN` 헤더로 되돌려보내는" 방식이다. cross-domain일 땐 FE가 **BE 도메인 쿠키를 못 읽어** 깨졌는데, 프록시로 same-origin이 되면 그 쿠키가 **FE 도메인 쿠키로 보여** `document.cookie`로 읽을 수 있다 → 정상 동작.

### 4. 쿠키 설정 조건 (배포)
same-origin(프록시)이면:
- `SameSite=Lax` — cross-site가 아니므로 `None` 불필요(오히려 Lax가 맞음)
- `Secure=true` — https니까
- **`Domain` 지정 안 함**(host-only) — 지정하면 BE 도메인에 묶여 FE 도메인에서 안 붙는다

### 5. 로컬 http의 Secure 함정
프록시는 CORS만 풀지 **쿠키의 `Secure`는 못 푼다**. 로컬 FE가 `http://localhost`면 `Secure` 쿠키(https 전용)가 저장이 안 돼 인증이 실패한다. 그래서:
- 로컬은 BE도 로컬로(둘 다 localhost) + `Secure=false`·`SameSite=Lax`가 표준
- Render 배포 BE를 로컬 FE와 붙이려면 로컬 FE를 https로(`next dev --experimental-https`)

## 예시 코드
Pulse 배포(Vercel↔Render) — 프록시 + 쿠키 env:
```
# Render(BE) 환경변수
AUTH_COOKIE_SECURE=true
AUTH_COOKIE_SAME_SITE=Lax      # 프록시라 None 아님
# CORS_ALLOWED_ORIGINS 는 안 넣어도 됨(프록시면 미사용)
```
CSRF 쿠키(`XSRF-TOKEN`)도 같은 `SameSite=Lax`로 나가는지 확인(SecurityConfig가 쿠키 정책을 환경변수로 따르게 돼 있으면 자동으로 맞음).

## 확인 문제
1. 프록시로 same-origin을 만들면 CORS가 왜 "불필요"해지나?
2. cross-domain에선 깨지던 CSRF double-submit이 프록시로는 왜 동작하나?
3. 프록시를 썼는데도 로컬 http FE + Render BE 조합에서 인증이 안 되는 이유는?

<details><summary>답</summary>

1. 브라우저가 자기 origin(FE 도메인)으로만 요청하고 실제 BE 전달은 서버간(Vercel→Render)에서 일어난다. 브라우저 입장에선 cross-origin이 아니라 CORS 프리플라이트·헤더가 애초에 발생하지 않으므로 허용 origin 설정이 필요 없다.

2. double-submit은 FE가 BE의 `XSRF-TOKEN` 쿠키 값을 읽어 헤더로 되돌려보내는 방식인데, cross-domain에선 FE가 BE 도메인 쿠키를 못 읽어 깨진다. 프록시로 same-origin이 되면 그 쿠키가 FE 도메인 쿠키로 보여 `document.cookie`로 읽을 수 있어 정상 동작한다.

3. 프록시는 CORS만 풀지 쿠키의 `Secure` 속성은 못 푼다. 로컬 FE가 http인데 BE가 `Secure` 쿠키(https 전용)를 내리면 브라우저가 저장을 안 해 인증이 실패한다. 로컬 FE를 https로 올리거나 로컬 BE(Secure=false)로 개발해야 한다.

</details>

## 더 볼 것
- [[cookie-based-auth]] — 왜 cross-domain에서 double-submit이 깨지는지의 근본
- [[spring-security-cookie-csrf]] — 서버 쪽 double-submit 구현
- [[nextjs-vs-node-fetch]] — FE fetch가 쿠키를 다루는 방식
