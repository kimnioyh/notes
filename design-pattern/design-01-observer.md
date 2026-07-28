# Design 01 — Observer (Pub-Sub)

> Day 1 · 앵커 예제: **Toast 알림 시스템**
> 코드: `src/patterns/observer/`

## 한 문장
객체(subject/store)의 상태가 바뀌면 등록된 구독자들에게 자동으로 알린다.
**발행자와 구독자는 서로를 모른다.**

## 구조
- **Store(subject)**: 구독자 목록을 들고 있고, 상태 변화 시 `notify()`.
- **subscribe(listener) → unsubscribe**: 구독 등록, 해제 함수 반환.
- **publish/show**: 상태 변경 + 알림.

```
버튼(발행자)  --show()-->  toastStore  --notify()-->  ToastContainer(구독자)
                            (서로 모름, prop 전달 없음)
```

## Toast 데모의 두 발행: show vs dismiss
| | `show` | `dismiss` |
|---|---|---|
| 하는 일 | 배열에 **추가** | 배열에서 **제거** |
| 인자 | message, type, ttl | id |
| 누가 부르나 | 발행자(버튼 등) | ① 토스트 클릭 ② `show`가 건 타이머(ttl 뒤) |
| 반환 | 새 `id` | 없음 |

연결고리: `show`가 `id`를 만들고 `setTimeout(() => dismiss(id), ttl)`을 예약한다.
- **자동 사라짐** = show가 걸어둔 타이머가 dismiss 호출
- **클릭 즉시 닫힘** = Container의 onClick이 같은 dismiss 호출
- 둘 다 끝에 `notify()`

## notify / listener는 무슨 일을 하나
`listener`는 우리가 만든 함수가 아니라 **React가 `subscribe`에 넣어준 콜백**이다
(`useSyncExternalStore`가 등록한 "store 바뀌었으니 다시 확인해" 신호선).

`notify()`가 `listener()`를 호출하면 React는:
1. `getSnapshot()`을 다시 읽는다 → 현재 상태
2. 직전 값과 **참조 비교**(`Object.is`)
3. 참조가 달라졌으면 → 구독 컴포넌트 **리렌더 예약**
4. 리렌더 시 훅이 새 값을 반환 → 화면 갱신

즉 `listener()` 호출 = "React야, store 확인하고 필요하면 다시 그려"라고 두드리는 것.
실제 렌더 여부는 React가 snapshot 비교로 판단한다.

## 왜 매번 새 배열을 만드나 (불변성)
- `show`/`dismiss`에서 `[...toasts, x]` / `filter`로 **새 배열**을 만드는 이유 =
  참조가 바뀌어야 위 3번에서 "바뀌었네" 판정 → 리렌더가 일어난다.
- 반대로 변화 없을 때 `getSnapshot`이 매번 새 배열을 주면 늘 "바뀜" 판정 → **무한 리렌더**.
  그래서 변화 없을 땐 반드시 같은 참조를 반환해야 한다.

## React에 이미 내장된 대응물
- `useSyncExternalStore(subscribe, getSnapshot)` — React 공식 외부 store 구독 훅.
  Redux/Zustand도 내부적으로 이걸 쓴다.
- `EventTarget` / `addEventListener` — 브라우저 기본 pub-sub.
- Context 자체도 값 변화를 구독자에게 흘리는 옵저버.

## 두 가지 구현 비교 (같은 패턴, 다른 배관)
| | 직접 만든 store | EventTarget 버전 |
|---|---|---|
| 구독자 저장 | `Set<() => void>` | `EventTarget` 내부 |
| 구독 | `listeners.add(l)` | `bus.addEventListener('change', l)` |
| 해제 | `listeners.delete(l)` | `bus.removeEventListener('change', l)` |
| 알림 | `for (l of listeners) l()` | `bus.dispatchEvent(new CustomEvent('change'))` |

`show`/`dismiss`/`getSnapshot`은 동일 — 바뀐 건 pub-sub 배관뿐.
`CustomEvent`는 `detail`에 payload를 실을 수 있어, snapshot 없이 순수 이벤트버스로도 확장 가능.

## 언제 쓰나
- 알림/토스트, 전역 이벤트 버스, 실시간 데이터(웹소켓) 브로드캐스트.
- 여러 컴포넌트가 같은 상태를 봐야 하는데 prop drilling이 싫을 때.

## 안티패턴 / 조심
- 이벤트 남발 → 흐름 추적 불가("누가 이걸 바꿨지?"). 지역 상태면 그냥 `useState`.
- unsubscribe 안 하면 메모리 누수. cleanup 필수.
- 대부분의 앱 전역 상태는 직접 만들지 말고 Context/상태 라이브러리로. 직접 구현은 학습·초경량용.

## 다음과의 연결
Singleton(`design-02`)의 `toastStore`도 사실 **모듈 스코프 싱글턴**이다.
Observer = "상태 공유 + 자동 리렌더", Singleton = "상태 공유"만. 리렌더는 별개.
