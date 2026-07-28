# Design 02 — Singleton

> Day 2 · 앵커 예제: **ConfigService (앱 설정 단일 인스턴스)**
> 코드: `src/patterns/singleton/`

## 한 문장
어떤 것의 인스턴스를 앱 전체에서 **딱 하나만** 두고, 어디서 접근해도 같은 인스턴스를 돌려준다.

## 왜 필요한가
설정(config), 로거, API 클라이언트, 캐시처럼 "여러 개 생기면 곤란한" 것들.
컴포넌트마다 `new ConfigService()`를 하면 각자 다른 상태를 들고 따로 논다
→ A의 변경이 B에 안 보인다. 그래서 인스턴스가 하나여야 한다.

## 구현 방식 (덜 → 더 게으름)

### 1. 클래식 GoF
```ts
export class ConfigService {
  private static instance: ConfigService
  theme: 'light' | 'dark' = 'light'
  private constructor() {}
  static getInstance() {
    if (!ConfigService.instance) ConfigService.instance = new ConfigService()
    return ConfigService.instance
  }
  setTheme(t: 'light' | 'dark') { this.theme = t }
}
```
`private constructor`로 밖에서 `new` 차단 → 오직 `getInstance()`로만 접근.

### 2. 모듈 스코프 인스턴스 ✅ (대개 이거면 충분)
```ts
class ConfigServiceImpl { /* ... */ }
export const config = new ConfigServiceImpl()
```
**JS 모듈은 최초 import 때 한 번만 평가되고 캐시된다 → 모듈 자체가 이미 싱글턴.**
`getInstance()` 보일러플레이트가 불필요하다.

### 3. 객체 리터럴 (클래스도 필요 없을 때)
```ts
export const config = { theme: 'light', setTheme(t) { this.theme = t } }
```

## 정체성(identity)
싱글턴인지 확인 = 서로 다른 곳에서 가져온 참조가 `===` 로 같은가.
```ts
import { config } from './configService'
const a = config, b = config
a === b   // true — 같은 인스턴스
```

## `this` 메서드 vs 화살표 클로저 캡처
객체 리터럴에서 상태를 어디에 두느냐의 차이.

**this 방식** — 상태를 프로퍼티에, 메서드에서 `this.theme`:
```ts
export const config = {
  theme: 'light',
  setTheme(t) { this.theme = t },   // this = "누가 불렀나"에 의존
}
config.setTheme('dark')        // ✅ this = config
const { setTheme } = config
setTheme('dark')               // 💥 this = undefined → 런타임 에러
```

**화살표 캡처 방식** — 상태를 모듈 변수에, 접근자는 화살표로 그 변수를 캡처:
```ts
let theme: Theme = 'light'
export const config = {
  get theme() { return theme },
  setTheme: (t: Theme) => { theme = t },   // 화살표 → this 없음, theme을 직접 대입
}
```
화살표 함수엔 **자기 `this`가 없어서**, `this.theme`가 아니라 정의된 위치의 `theme` 변수를
렉시컬하게 캡처한다. → 호출 방식과 무관하게 안전.

| | this 메서드 | 화살표 캡처 |
|---|---|---|
| 읽기 | `config.theme` (깔끔) | `get theme` 게터 필요 |
| 견고함 | 호출 방식에 취약 | 어떻게 부르든 안전 |
| 정신 모델 | "this = 호출자" | "함수가 변수를 기억함" |

> `design-01`의 `toastStore`가 바로 이 캡처 방식이다(`this`가 한 번도 안 나옴).

## React에서의 핵심 함정
싱글턴 필드를 바꿔도 **React는 리렌더 안 한다**(구독이 없으니까).
```tsx
const [, force] = useState(0)
<button onClick={() => { config.setTheme('dark'); force(n => n + 1) }}>toggle</button>
<p>theme: {config.theme}</p>
```
강제 리렌더를 걸어야 값이 화면에 반영된다.
→ **"싱글턴 = 상태 공유"와 "리렌더 = 반응형"은 별개.**
반응형이 필요하면 Observer(구독)나 Context와 결합해야 한다.

## 언제 쓰나
- 전역 설정/로거/클라이언트 등 상태·연결을 공유해야 할 때.

## 안티패턴 / 조심
- **숨은 전역 상태**: 싱글턴은 결국 전역 변수. 테스트 시 상태가 남아 오염됨(테스트마다 reset 필요).
- 리액트에서 싱글턴만으론 반응형이 안 됨 → Observer/Context 결합 필요.
- `getInstance` 보일러플레이트를 굳이 쓰지 말 것. 모듈 export로 충분.

## 다음과의 연결
Observer(`design-01`)와 결합하면 "단일 인스턴스 + 변경 시 자동 리렌더"가 완성된다.
