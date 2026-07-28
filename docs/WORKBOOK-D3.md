# 🧩 D3 워크북 — 라이브러리 소비 + CRUD API + 결제 연결

> 목표: ①앱이 로컬 라이브러리를 workspace로 소비 ②구독 CRUD API(Route Handler) ③결제창 호출.

---

## ✅ 이미 된 것
- 라이브러리 workspace 링크 (`package.json` → `"workspace:*"`)
- `app/api/subscriptions/route.ts` (GET/POST) ← 네가 POST 채움 ✔
- `app/api/subscriptions/[id]/route.ts` (PATCH) ← 네가 채움 ✔
- 성공/실패 페이지, 테스트 페이지 골격

## ✍️ 남은 것: `app/checkout-test.tsx`
`PaymentButton`에 props 6개 연결 (파일 안 TODO 참고).
```tsx
clientKey={process.env.NEXT_PUBLIC_TOSS_CLIENT_KEY!}
successUrl={`${origin}/payment/success`}
failUrl={`${origin}/payment/fail`}
amount={1000}
orderId={`test_${Date.now()}`}
orderName="테스트 결제"
```

> ⚠️ 먼저 `.env`에 `NEXT_PUBLIC_TOSS_CLIENT_KEY="test_ck_..."` 넣어야 결제창이 떠.

---

## 📚 이번에 익힌 개념 3가지

### 1) Route Handler = 내장 백엔드
`app/api/.../route.ts`에서 `export async function GET/POST/PATCH` → 그게 API 엔드포인트.
express `app.get(...)` 을 파일 규칙으로 대체 (07_groq의 그 서버가 앱 안으로 들어온 셈).

### 2) `params`/`searchParams`는 Promise (Next 15+)
```ts
{ params }: { params: Promise<{ id: string }> }
const { id } = await params;   // ★ await 필수 — 안 하면 id가 undefined
```

### 3) 서버 vs 클라이언트 경계
- 페이지(`page.tsx`, success/fail) = **서버 컴포넌트**(기본) → DB·async 직접, JS 안 실림.
- `checkout-test.tsx` = **client**(`'use client'`) → `PaymentButton`이 훅을 쓰니까.
- 규칙: **서버가 기본, 상호작용(훅/이벤트)만 client 섬으로**.

---

## 🔍 검증

### A. 결제창 (브라우저)
```bash
pnpm --filter dashboard dev
```
→ http://localhost:3000 → **결제하기** 클릭 → 토스 결제창 오픈 →
   테스트 결제 완료 → `/payment/success` 로 리다이렉트되며 orderId/amount/paymentKey 표시.
   (취소하면 `/payment/fail`)

### B. CRUD API (터미널, dev 켠 상태에서)
> Windows는 `curl.exe` 로 (PowerShell의 `curl`은 다른 명령).
```bash
# 등록
curl.exe -X POST http://localhost:3000/api/subscriptions -H "Content-Type: application/json" -d "{\"name\":\"넷플릭스\",\"amount\":17000,\"cycle\":\"MONTHLY\",\"nextBillAt\":\"2026-08-01\"}"

# 목록
curl.exe http://localhost:3000/api/subscriptions
```
→ 등록이 201 + 객체, 목록에 방금 것이 보이면 성공. (이 데이터는 D4 목록 화면에서 씀)

---

다 되면 **"D3 다했어"** — 리뷰하고 D4(목록+폼+TanStack Query)로 갈게.
막히는 지점(특히 결제창/환경변수) 있으면 바로 말해줘.
