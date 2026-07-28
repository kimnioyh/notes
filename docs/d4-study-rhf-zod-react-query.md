# D4 정리 — React Hook Form · Zod · TanStack Query

> 대중교통용 요약. 개념 → 왜 → 우리 코드 순서. 면접에서 "설명할 수 있는" 수준이 목표.

---

## 0. 한 문장 정리

- **Zod** = 데이터 모양·규칙을 코드로 정의하고 검증 (런타임 타입 검사기).
- **React Hook Form (RHF)** = 폼 상태·검증·제출을 관리 (리렌더 최소화).
- **TanStack Query (react-query)** = 서버 데이터 조회·캐시·갱신 관리.
- 셋이 만나는 지점: **Zod로 규칙 정의 → RHF가 그 규칙으로 검증 → 통과한 값을 react-query mutation으로 서버에 전송.**

---

## 1. Zod

### 개념
스키마(데이터 규칙)를 객체로 선언하면, 런타임에 실제 값이 그 규칙을 지키는지 검사해줌.
TypeScript 타입은 **컴파일 타임**에만 존재 → 서버 응답·폼 입력 같은 **런타임 값**은 못 지킴. Zod가 그 빈틈을 메움.

### 핵심 문법
```ts
import { z } from "zod";

const schema = z.object({
  name: z.string().min(1, "필수"),        // 문자열, 1글자 이상, 에러메시지
  amount: z.coerce.number().int().min(1), // 숫자로 변환 후 정수·1이상
  cycle: z.enum(["MONTHLY", "YEARLY"]),   // 둘 중 하나만
});

schema.parse(value);       // 실패 시 throw
schema.safeParse(value);   // { success, data | error } 반환 (throw 안 함)
```

### `coerce`가 왜 중요한가 (우리 코드 핵심)
`<input type="number">`의 value도 실제로는 **문자열** `"9900"`으로 들어옴.
`z.coerce.number()`는 검증 전에 `Number()`로 변환해줌.
→ **검증 전 타입(string) ≠ 검증 후 타입(number)**. 이 차이가 나중에 RHF 제네릭 3개로 이어짐.

### 타입 자동 추론 (Zod의 킬러 기능)
```ts
export type Input  = z.input<typeof schema>;   // 변환 전 (amount: 아직 unknown/string)
export type Output = z.output<typeof schema>;  // 변환 후 (amount: number)
// z.infer === z.output
```
스키마 하나로 검증 + 타입 둘 다 얻음. 타입을 따로 손으로 안 써도 됨 = 진실의 원천 1개.

---

## 2. React Hook Form

### 개념
폼을 **비제어(uncontrolled)** 방식으로 다룸 → 입력할 때마다 리렌더 안 함 → 빠름.
`register`로 input을 폼에 등록만 해두고, 값은 ref로 모아뒀다가 제출 때 한 번에 읽음.

### 핵심 3개
```ts
const { register, handleSubmit, formState: { errors }, reset } = useForm({
  resolver: zodResolver(schema),   // ★ Zod와 연결
  defaultValues: { cycle: "MONTHLY" },
});
```
- **register("name")** → `<input {...register("name")} />` : 이 input을 폼에 연결.
- **handleSubmit(onValid)** → `<form onSubmit={handleSubmit(fn)}>` : **검증 통과 시에만** fn 실행. 실패하면 errors 채우고 fn 안 부름.
- **formState.errors** → `errors.name?.message` : Zod가 뱉은 메시지 표시.
- **reset()** → 제출 성공 후 폼 비우기.

### zodResolver = 다리
RHF는 검증 로직을 몰라도 됨. `resolver`에 zodResolver(schema)를 꽂으면
RHF가 제출할 때 그 스키마로 검증을 위임함. Zod ↔ RHF 연결 어댑터.

### 제네릭 3개 (우리가 만난 타입 에러의 정체)
```ts
useForm<FormInput, unknown, Output>({ ... })
//       ↑입력값     ↑컨텍스트  ↑검증·변환 후 값
```
`coerce`로 입력≠출력이라 둘을 각각 알려줘야 함.
`handleSubmit((values) => ...)`의 `values`는 **Output**(amount: number)으로 들어옴.
제네릭을 1개만 주면 "string 넣었는데 number 기대함" 충돌 → 그게 아까 그 에러.

---

## 3. TanStack Query (react-query)

### 개념
"서버 상태"를 위한 도구. 서버 데이터는 로컬 state와 다름 — 캐시, 재요청, 로딩/에러,
중복 요청 제거를 다 신경 써야 함. react-query가 그걸 대신함. `useState`+`useEffect`+`fetch` 조합의 상위호환.

### 세팅 (앱 1회)
```tsx
"use client";
const [client] = useState(() => new QueryClient());
<QueryClientProvider client={client}>{children}</QueryClientProvider>
```
`useState(() => ...)`로 감싸는 이유: 리렌더마다 new 하면 캐시가 날아가서. 최초 1회만 생성.

### 조회 — useQuery
```ts
const { data, isLoading, isError } = useQuery({
  queryKey: ["subscriptions"],   // 캐시 식별자 (배열)
  queryFn: listSubscriptions,    // 실제 fetch 함수
});
```
- **queryKey** = 이 데이터의 이름표. 같은 key면 캐시 공유, 이 key로 나중에 무효화.
- **queryFn** = Promise 반환 함수. 성공하면 data, 실패하면 isError.
- 로딩/에러/캐시/자동 리페치(창 포커스 등) 전부 자동.

### 쓰기 — useMutation
```ts
const qc = useQueryClient();
const mutation = useMutation({
  mutationFn: createSubscription,  // POST/PATCH/DELETE
  onSuccess: () => {
    qc.invalidateQueries({ queryKey: ["subscriptions"] }); // 목록 새로고침
    reset();
  },
});
mutation.mutate(values);  // 실행
mutation.isPending;       // 진행 중? (버튼 disable용)
```

### 왜 useQuery / useMutation를 나누나
- **useQuery = 읽기(GET)**: 캐시하고 자동으로 다시 가져옴.
- **useMutation = 쓰기(POST/PATCH/DELETE)**: 서버 상태를 바꾸는 행위. 캐시 안 함.
역할이 달라서 API도 다름.

### 왜 `invalidateQueries`?
등록/해지 성공 후 **캐시를 "낡음" 표시** → useQuery가 자동으로 다시 GET → 서버 실제 상태로 맞춤.
서버가 만든 id·createdAt·status를 확실히 반영. 목록에 직접 끼워넣는 것(optimistic)보다 안전하고 코드 짧음.

---

## 4. 전체 흐름 (우리 D4)

```
사용자 입력
  │  register로 폼에 연결된 input들
  ▼
[제출] handleSubmit
  │  → zodResolver(schema)로 검증
  │     실패 → errors 표시, 여기서 멈춤
  │     성공 → values(검증·변환 완료, amount:number)
  ▼
mutation.mutate(values)
  │  → createSubscription → POST /api/subscriptions
  ▼
onSuccess
  │  → invalidateQueries(["subscriptions"])
  ▼
useQuery가 자동 재조회 → 목록에 새 구독 반영
```

---

## 5. 면접 예상 질문 셀프체크

1. Zod는 왜 필요? → TS 타입은 컴파일 타임뿐, **런타임 값**(폼·API 응답)은 못 지켜서. Zod가 런타임 검증.
2. RHF가 빠른 이유? → 비제어 방식, 입력마다 리렌더 안 함.
3. `z.coerce`? → input value는 항상 string. 검증 전 숫자 변환. 그래서 입력≠출력 타입.
4. useQuery vs useMutation? → 읽기(캐시) vs 쓰기(서버 상태 변경).
5. invalidateQueries의 의미? → 캐시 무효화 → 재조회 → 서버가 진실. 안전한 갱신.
6. QueryClient를 useState로 감싼 이유? → 리렌더마다 재생성 방지, 캐시 유지.

---

*SubPay D4 · 김효인 포트폴리오*
