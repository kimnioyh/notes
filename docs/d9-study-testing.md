# D9 정리 — 테스트: Vitest · React Testing Library · Playwright

> 대중교통용 요약. 개념 → 왜 → 우리 코드 순서. 면접에서 "설명할 수 있는" 수준이 목표.
> 이력서 공백을 메우는 차별화 포인트 → "품질 의식"을 실물 테스트로 증명.

---

## 0. 한 문장 정리

- **유닛 테스트** = 작은 조각(함수/훅) 하나를 격리해서 검증. 빠르고 많이.
- **E2E 테스트** = 진짜 브라우저로 사용자처럼 클릭·입력하며 전체 흐름 검증. 느리고 적게.
- 세 도구: **Vitest**(유닛 러너) · **React Testing Library**(컴포넌트/훅을 사용자 관점에서) ·
  **Playwright**(E2E, 실제 브라우저 자동화).
- 우리 D9: 라이브러리 훅(`usePayment`)은 **Vitest+RTL 유닛**, 앱 구독 흐름은 **Playwright E2E**.

---

## 1. 왜 나눠서 테스트하나 (테스트 피라미드)

```
        /\        E2E      ← 적게 (느림·불안정하지만 "진짜" 통합 검증)
       /--\
      /----\   통합/컴포넌트
     /------\
    /--------\   유닛        ← 많이 (빠름·안정, 로직 조각 검증)
```

- 아래로 갈수록 **빠르고 안정** → 많이 둠.
- 위로 갈수록 **느리고 깨지기 쉬움**(외부 의존) → 핵심 흐름만 소수.
- 그래서 우리도 훅 로직은 유닛으로 촘촘히, 사용자 여정은 E2E 1개로.

> 면접 한 줄: **"로직 단위는 유닛으로 빠르게, 사용자 여정은 E2E로 한 번 — 피라미드대로 비용/안정성 균형."**

---

## 2. Vitest — 유닛 테스트 러너

### 개념
Jest 계열의 테스트 러너인데 **Vite/esbuild 기반이라 빠르고 설정이 적음**. TS를 별도 컴파일 없이 바로 실행.

### 핵심 문법
```ts
import { describe, it, expect, vi, beforeEach } from "vitest";

describe("그룹 이름", () => {
  beforeEach(() => { vi.clearAllMocks(); }); // 각 테스트 전 초기화
  it("무엇을 한다", () => {
    expect(1 + 1).toBe(2);          // 값 단언
    expect(fn).toHaveBeenCalledWith(x); // 호출 인자 단언
  });
});
```
- **describe/it** = 그룹/케이스. **expect(...).matcher** = 단언.
- **vi.fn()** = 가짜 함수(호출 여부·인자 기록). **vi.mock("모듈")** = 모듈 통째로 가짜로 교체.
- 실행: `vitest run`(1회) / `vitest`(watch).

### jsdom 환경이 왜 필요한가 (우리 설정)
훅/컴포넌트는 렌더할 **DOM**이 필요한데 Node엔 DOM이 없음. `environment: "jsdom"`으로 브라우저 유사 DOM을 제공.
```ts
// vitest.config.ts
export default defineConfig({ test: { environment: "jsdom", globals: true } });
```

---

## 3. React Testing Library (RTL)

### 개념·철학
"**사용자가 보는 대로 테스트**하라." 내부 상태(state 변수)가 아니라 **화면에 나타난 결과/동작**을 검증.
→ 리팩터링해도 동작만 같으면 테스트가 안 깨짐 (구현 세부에 결합하지 않음).

### 훅 테스트: `renderHook`
컴포넌트 없이 훅만 렌더해서 반환값을 관찰.
```ts
const { result } = renderHook(() => usePayment(opts));
result.current.ready;          // 현재 반환값
await waitFor(() => expect(result.current.ready).toBe(true)); // 비동기 상태 변화 대기
await act(async () => { await result.current.requestPayment(...); }); // 상태 바꾸는 호출은 act로 감쌈
```
- **waitFor** = "조건이 참이 될 때까지" 재시도 대기 (비동기 setState 반영 기다림).
- **act** = React 상태 업데이트를 감싸 "렌더가 안정된 뒤" 단언하게 함 (경고 방지).

---

## 4. 모킹 — 외부 의존 끊기 (D9 핵심)

### 왜 토스 SDK를 모킹했나
`usePayment`는 `loadTossPayments`(외부 SDK)를 부름. 테스트에서 진짜로 부르면:
네트워크 필요, 실제 결제창 뜸, 결과가 매번 다름 → **느리고 불안정**.
→ SDK를 **가짜로 교체**하고 "우리 훅이 SDK를 **올바른 인자로 부르는가**"만 검증 = 우리 코드의 책임에 집중.

```ts
// 모듈 통째 교체 (vi.mock 팩토리는 파일 최상단으로 호이스팅됨)
vi.mock("@tosspayments/tosspayments-sdk", () => ({
  ANONYMOUS: "ANONYMOUS",
  loadTossPayments: vi.fn(),
}));

const loadMock = vi.mocked(loadTossPayments);
loadMock.mockResolvedValue({ payment: paymentMock }); // 준비됨 시나리오
loadMock.mockReturnValue(new Promise(() => {}));       // 영원히 pending = "준비 전" 시나리오
```

### 우리가 검증한 3가지
1. `ready`는 false로 시작 → SDK 로드 후 true (라이프사이클).
2. `requestPayment`가 `{amount, orderId, orderName}` → **토스 규격**(method CARD, `{value, currency:"KRW"}`, successUrl/failUrl 주입)으로 매핑.
3. SDK 준비 전 호출 시 **"결제 모듈 준비 전" 에러**.

> 면접 한 줄: **"외부 SDK는 모킹해 경계만 검증 — 결제창을 안 띄우고도 결제 회귀를 막는다."**

---

## 5. Playwright — E2E

### 개념
**진짜 브라우저**(Chromium 등)를 코드로 조종해 사용자처럼 클릭/입력하고 화면을 단언. 전체 스택을 관통 검증.

### 시맨틱 로케이터 (접근성과 직결)
요소를 CSS 클래스가 아니라 **역할/라벨**로 찾음 → 접근성 좋은 마크업이 곧 테스트하기 좋은 마크업.
```ts
await page.getByLabel("서비스명").fill("넷플릭스");     // aria-label / label
await page.getByRole("button", { name: "구독 등록" }).click(); // 역할+이름
await expect(row).toContainText("해지됨");             // 자동 재시도 단언
```
- **getByLabel/getByRole** = 사람이 인식하는 방식으로 요소 선택 (D8의 `aria-label`이 여기서 그대로 쓰임).
- **자동 대기**: `expect(...).toBeVisible()` 등은 조건 충족까지 자동 재시도 → 수동 sleep 불필요.

### webServer (설정)
테스트 시작 시 앱을 자동 기동, 끝나면 정리.
```ts
webServer: { command: "pnpm dev", url: "http://localhost:3000", reuseExistingServer: true }
```

### 우리 E2E 시나리오
구독 등록 → 목록에 반영 → 해지 시 "(해지됨)". 폼 → Route Handler → Prisma → TanStack Query 재조회까지 **풀스택 결정적 검증**.

> 면접 한 줄: **"E2E는 외부 결제창 같은 불안정 요소 대신, 우리가 통제하는 풀스택 경로를 실제 브라우저로 검증 — 시맨틱 로케이터라 a11y와 시너지."**

---

## 6. 전체 흐름 (우리 D9)

```
[라이브러리]  usePayment.test.ts (Vitest + RTL)
   토스 SDK 모킹 → renderHook → ready/매핑/에러 3케이스        ← 유닛 (빠름·격리)

[앱]  e2e/subscription.spec.ts (Playwright)
   실제 브라우저 → /subscriptions → 폼 입력·제출 → 목록 확인 → 해지  ← E2E (풀스택)

[검증]  pnpm -r build → 위젯(tsup) + 앱(next build) strict 타입 0
```

---

## 7. 면접 예상 질문 셀프체크

1. 유닛 vs E2E? → 조각 격리 검증(빠름·많이) vs 실제 브라우저 전체 흐름(느림·적게). 피라미드.
2. 왜 외부 SDK를 모킹? → 네트워크/결제창 없이, 우리 코드가 SDK를 올바르게 부르는지에 집중. 안정·빠름.
3. `vi.mock`은 왜 최상단에 안 써도 되나? → 팩토리가 파일 최상단으로 **호이스팅**되기 때문.
4. RTL 철학? → 구현(state)이 아니라 **사용자가 보는 동작/결과**를 테스트 → 리팩터링에 강함.
5. `waitFor`/`act`? → 비동기 상태 반영을 기다리고(waitFor), 상태 변경 호출을 감싸(act) 안정된 뒤 단언.
6. Playwright 로케이터를 왜 role/label로? → 접근성 있는 마크업 = 테스트 가능한 마크업. 클래스는 잘 바뀜.
7. E2E에서 결제 승인을 왜 안 넣었나? → 외부 결제창 의존은 불안정 → 승인 로직은 유닛/수동으로, E2E는 통제 가능한 풀스택 경로.

---

*SubPay D9 · 김효인 포트폴리오*
