# 워크북 — Observer (pub-sub) → Toast

> 목표: `toastStore.ts`와 `ObserverDemo.tsx`를 **직접 타이핑하며** 만든다.
> 정답은 각 스텝의 `<details>`에 접어뒀다. 먼저 스스로 써보고, 막히면 펼친다.
> (이 폴더엔 이미 완성본이 있다. 제대로 연습하려면 두 파일을 지우거나 비우고 시작.)

먼저 `NOTES.md`의 개념을 읽고 온다.

---

## Step 1 — store의 뼈대

`toastStore.ts`에 상태와 구독자 목록을 모듈 스코프 변수로 둔다.

✍️ **직접 해보기**
- `Toast` 타입을 정의한다: `id: number`, `type: 'success'|'error'|'info'`, `message: string`.
- 모듈 스코프에 `toasts: Toast[]`, `listeners: Set<() => void>`, `nextId` 를 선언한다.

<details><summary>정답 보기</summary>

```ts
export type ToastType = 'success' | 'error' | 'info'
export type Toast = { id: number; type: ToastType; message: string }

let toasts: Toast[] = []
const listeners = new Set<() => void>()
let nextId = 1
```
왜 모듈 스코프? import 하는 모든 파일이 같은 인스턴스를 공유 → 자연스러운 Singleton.
</details>

---

## Step 2 — subscribe / getSnapshot

React가 외부 store를 구독하는 계약을 만든다.

✍️ **직접 해보기**
- `subscribe(listener)` : listener를 등록하고 **해제 함수**를 반환.
- `getSnapshot()` : 현재 `toasts`를 반환.
- ⚠️ 함정: 변화가 없을 땐 반드시 **같은 배열 참조**를 돌려줘야 한다. 왜일까? (안 그러면?)

<details><summary>정답 보기</summary>

```ts
export const toastStore = {
  subscribe(listener: () => void) {
    listeners.add(listener)
    return () => { listeners.delete(listener) }
  },
  getSnapshot() {
    return toasts
  },
}
```
매번 새 배열을 반환하면 `useSyncExternalStore`가 "값이 바뀌었다"고 판단 → 무한 렌더 루프.
그래서 상태를 바꿀 때(Step 3)만 새 배열로 교체한다.
</details>

---

## Step 3 — show / dismiss (발행)

상태를 바꾸고 구독자에게 알린다.

✍️ **직접 해보기**
- `show(message, type, ttl=3000)` : 새 토스트를 배열에 **불변으로** 추가(`[...toasts, new]`), 모든 listener 호출, `ttl`초 뒤 자동 dismiss.
- `dismiss(id)` : 해당 id 제거. 없으면 참조 유지(불필요한 렌더 방지).

<details><summary>정답 보기</summary>

```ts
function notify() {
  for (const l of listeners) l()
}

// toastStore 안에 추가:
  show(message: string, type: ToastType = 'info', ttl = 3000) {
    const id = nextId++
    toasts = [...toasts, { id, type, message }]
    notify()
    if (ttl > 0) setTimeout(() => toastStore.dismiss(id), ttl)
    return id
  },
  dismiss(id: number) {
    const next = toasts.filter((t) => t.id !== id)
    if (next.length === toasts.length) return
    toasts = next
    notify()
  },
```
</details>

---

## Step 4 — React에서 구독 (`useSyncExternalStore`)

`ObserverDemo.tsx`에서 store를 React 상태처럼 읽는다.

✍️ **직접 해보기**
- `useToasts()` 훅을 만든다: `useSyncExternalStore(subscribe, getSnapshot)`.

<details><summary>정답 보기</summary>

```tsx
import { useSyncExternalStore } from 'react'
import { toastStore } from './toastStore'

const useToasts = () =>
  useSyncExternalStore(toastStore.subscribe, toastStore.getSnapshot)
```
이게 Redux/Zustand가 내부적으로 쓰는 바로 그 훅이다.
</details>

---

## Step 5 — 구독자(Container)와 발행자(버튼)

✍️ **직접 해보기**
- `ToastContainer` : `useToasts()`로 목록을 받아 렌더, 클릭 시 `dismiss`.
- `ObserverDemo` : success/error/info 버튼 3개, 각각 `toastStore.show(...)`.
- 핵심 확인: **버튼과 Container는 서로를 import 하지 않는다**. store만 공유.

<details><summary>정답 보기</summary>

완성본 `ObserverDemo.tsx` 참고. 버튼(발행자)은 Container의 존재를 모르고,
Container(구독자)는 누가 show를 불렀는지 모른다. 둘의 유일한 접점은 store.
</details>

---

## 체크포인트 ✅
`npm run dev` → `/observer`
- [ ] 버튼 누르면 오른쪽 아래 토스트가 뜬다
- [ ] 토스트 클릭 시 즉시 닫힌다
- [ ] 3초 뒤 자동으로 사라진다
- [ ] 여러 개 빠르게 누르면 쌓인다

## 도전 과제 (여유되면)
1. 같은 store를 구독하는 **두 번째 Container**를 다른 위치에 추가 → 둘 다 자동 갱신되는지 확인(옵저버의 핵심).
2. `EventTarget` + `CustomEvent`만으로 store를 다시 구현해보고 비교.
3. `ttl`을 토스트마다 다르게, 그리고 남은 시간 프로그레스 바 추가.
