# Next.js fetch vs Node.js fetch (같은 표준, 다른 동작)

**한 문장**: 같은 WHATWG `fetch` API지만, Next는 native fetch를 **패치해서 캐싱/재검증을 얹었고**(서버 전용), Node fetch는 브라우저 fetch와 달리 **쿠키 자동관리가 없어** SSR에서 인증 쿠키를 수동으로 넘겨야 한다.

## 왜 헷갈렸나
쿠키 인증을 붙이면서 "우리 FE는 Next인데 이 쿠키/CSRF가 거기서도 그대로 되나?"가 안 잡혔다. Next는 SSR+CSR 하이브리드라 fetch가 **어디서 도느냐**(브라우저 vs Node 서버)에 따라 쿠키 동작이 갈린다.

## 핵심

### 1. Next fetch = native fetch + 확장 (서버 사이드)
App Router 서버 컴포넌트에서 fetch에 추가 옵션이 붙는다:
- `fetch(url, { next: { revalidate: 60, tags: ['x'] } })` — ISR/재검증·캐시태그 (Next 전용)
- `cache: 'force-cache' | 'no-store'` — Next 데이터 캐시 연동
- **요청 메모이제이션** — 한 렌더에서 같은 fetch 중복 호출 자동 dedupe
- **기본 캐싱 정책이 다름** — Next 13/14는 서버 fetch 기본 캐시, **Next 15부턴 기본 no-store**
- → 이 확장은 **서버에서만** 적용. 클라(브라우저) 컴포넌트의 fetch는 그냥 브라우저 native fetch.

### 2. Node fetch vs 브라우저 fetch — 표면 API는 같은데 쿠키가 다르다
- 표준(Request/Response/headers/body)은 동일. Node 18+는 undici 기반 global fetch.
- **결정적 차이: 쿠키 자동관리.** 브라우저 fetch는 쿠키 저장소가 있어 `credentials: 'include'`면 알아서 쿠키를 첨부. **Node fetch(=서버 사이드)엔 쿠키 저장소가 없어** 자동으로 안 붙는다.

### 3. 그래서 인증 쿠키에 이렇게 걸린다
- **클라 컴포넌트에서 BE 호출** → 브라우저 fetch `credentials:'include'` → accessToken 쿠키 자동 전송 ✅
- **서버 컴포넌트/SSR에서 BE 호출** → Node fetch라 브라우저 쿠키가 **자동으로 안 넘어감** → 들어온 요청의 쿠키를 `next/headers`의 `cookies()`로 읽어 **직접 `Cookie` 헤더에 실어야** 함.
- 인증이 필요한 API를 **SSR로 부르면** 쿠키가 안 붙어 401 날 수 있다. "그 호출을 클라에서 하나 서버에서 하나"를 먼저 봐야 한다.

## 예시 코드
Pulse: FE(Next)의 인증 필요 호출이 전부 클라 컴포넌트라 `credentials:'include'`만으로 충분(쿠키 자동 전송). 서버에서 인증 API를 안 불러 SSR 쿠키 포워딩은 불필요. 나중에 대시보드를 SSR 프리페치하면 그때만:

```ts
// 서버 컴포넌트에서 인증 API 호출 시 (쿠키 수동 포워딩)
import { cookies } from 'next/headers';
const res = await fetch(`${API}/auth/me`, {
  headers: { Cookie: cookies().toString() },   // 브라우저 쿠키를 서버 fetch에 직접 전달
});
```

## 확인 문제
1. Next의 fetch가 native fetch와 다른 점 한 가지와, 그 확장이 적용되는 위치는?
2. 브라우저에서 `credentials:'include'`로 잘 가던 인증 API가 서버 컴포넌트에서 부르면 401이 날 수 있는 이유는?

<details><summary>답</summary>

1. `next: { revalidate, tags }` 캐시/재검증 옵션(또는 요청 메모이제이션·기본 캐싱 정책)을 얹었다. 이 확장은 **서버 사이드(서버 컴포넌트/route handler)**에서만 적용되고, 클라 컴포넌트의 fetch는 브라우저 native fetch 그대로다.

2. 서버 컴포넌트의 fetch는 Node fetch라 브라우저 쿠키 저장소가 없어 accessToken 쿠키가 자동으로 안 붙는다. `cookies()`로 읽어 `Cookie` 헤더에 직접 실어줘야 인증이 통과한다.

</details>

## 더 볼 것
- [[cookie-based-auth]] — 왜 쿠키가 브라우저에서만 자동으로 붙는지(도메인·SameSite)
