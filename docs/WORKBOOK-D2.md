# 🧩 D2 워크북 — 결제 라이브러리 코어

> 목표: `usePayment` 훅 + `<PaymentButton>` 을 완성해서 **토스 결제창을 여는** 재사용 라이브러리를 만든다.
> 타입은 이미 설계돼 있음(`types.ts`). 너는 **구현 로직(TODO)** 만 채운다.

---

## 📐 이 라이브러리의 구조 (한눈에)

```
소비자(앱)
  │  <PaymentButton clientKey successUrl failUrl amount orderId orderName />
  ▼
PaymentButton.tsx  ── usePayment(options) ──►  usePayment.ts
                                                 │  ① SDK 로드 → payment 객체 (ref에 보관)
  버튼 클릭                                       │  ② requestPayment() → 토스 결제창 오픈
     └──── requestPayment({amount,orderId,orderName}) ──►┘
                                                          │
                                              성공 → successUrl 로 리다이렉트
                                              실패 → failUrl 로 리다이렉트
```

**왜 훅과 컴포넌트를 나눴나?**
- `usePayment` = 로직(재사용·테스트 쉬움). `<PaymentButton>` = 그 훅을 쓰는 기본 UI.
- 소비자가 버튼 디자인을 원하는 대로 하려면 `usePayment` 만 써도 됨 → **유연한 라이브러리 API**.

---

## ✍️ 채울 파일 2개

### 1) `src/usePayment.ts`
- **TODO(1)** `useEffect` 안: 토스 SDK 로드 → `payment` 객체를 `paymentRef` 에 저장 → `setReady(true)`.
  - `loadTossPayments` 는 Promise라서 `useEffect` 콜백에서 바로 `await` 못 함 → **async IIFE**(즉시실행 async 함수)로 감싼다.
  - 언마운트 뒤 setState 하면 경고 → `alive` 가 `true` 일 때만 반영.
- **TODO(2)** `requestPayment`: `payment` 가 `null` 이면 `throw`.
- **TODO(3)** `payment.requestPayment({...})` 로 결제창 오픈. 마지막 임시 `throw` 줄 삭제.

### 2) `src/PaymentButton.tsx`
- **TODO(1)** `usePayment(options)` 호출.
- **TODO(2)** async 클릭 핸들러에서 `requestPayment({ amount, orderId, orderName })`.
- **TODO(3)** `disabled={!ready || disabled}`.
- **TODO(4)** `onClick` 연결.

> 💡 `PaymentButton` 의 `...options` 트릭: `amount/orderId/orderName/children/className/disabled` 를
> 구조분해로 빼면, 남은 `options` 가 정확히 `UsePaymentOptions`(clientKey·successUrl·failUrl·customerKey)가 된다.

---

## ✅ 검증

```bash
cd packages/react-payment-widget
pnpm build
```
- 성공하면 `dist/` 에 `index.js`(ESM) + `index.cjs`(CJS) + `index.d.ts`(타입) 재생성됨.
- 타입 에러가 남아있으면 tsup이 알려줌 → 그게 워크북의 "빨간불".

다 되면 **"D2 다했어"** 라고 해줘. 내가 리뷰하고 앱에 연결(D3)로 넘어갈게.

---

## 🆘 막히면 (솔루션)

<details 없이 아래에 그대로 둠 — 최대한 직접 쳐보고, 정말 막힐 때만 참고.

**usePayment.ts — TODO(1)**
```ts
(async () => {
  const toss = await loadTossPayments(clientKey);
  const payment = toss.payment({ customerKey: customerKey ?? ANONYMOUS });
  if (alive) {
    paymentRef.current = payment;
    setReady(true);
  }
})();
```

**usePayment.ts — TODO(2)+(3)** (임시 throw 줄은 삭제)
```ts
if (!payment) throw new Error("결제 모듈이 아직 준비되지 않았습니다.");

await payment.requestPayment({
  method: "CARD",
  amount: { value: params.amount, currency: "KRW" },
  orderId: params.orderId,
  orderName: params.orderName,
  successUrl,
  failUrl,
});
```

**PaymentButton.tsx**
```tsx
const { ready, requestPayment } = usePayment(options);

const handleClick = async () => {
  await requestPayment({ amount, orderId, orderName });
};

// return 부분
<button
  type="button"
  className={className}
  disabled={!ready || disabled}
  onClick={handleClick}
>
  {children ?? "결제하기"}
</button>
```
