# 워크북 — Singleton

> 목표: 앱 설정을 들고 있는 `ConfigService`를 만들고, "어디서 가져와도 같은 인스턴스"임을
> 직접 확인한다. 클래식 방식 → 모듈 스코프 방식으로 게을러지는 과정을 느껴본다.
> 먼저 스스로 타이핑하고, 막히면 `<details>` 정답을 펼친다.

먼저 `NOTES.md`를 읽고 온다. 작업 파일: `configService.ts`(로직) + `Demo.tsx`(화면).

---

## Step 0 — 문제 체감하기

✍️ **생각해보기** (코드 X)
- `class ConfigService { theme = 'light' }` 를 컴포넌트 A와 B에서 각각 `new` 하면?
- A에서 `theme='dark'`로 바꾸면 B의 theme은? → **왜 싱글턴이 필요한지** 한 문장으로 NOTES에 적기.

<details><summary>정답</summary>
각자 다른 인스턴스라 A의 변경이 B에 안 보인다. 설정은 하나로 공유돼야 하므로 인스턴스가 하나여야 한다.
</details>

---

## Step 1 — 클래식 GoF 싱글턴

✍️ **직접 해보기** — `configService.ts`
- `class ConfigService` 에 `private static instance`, `private constructor`, `static getInstance()`.
- 필드: `theme: 'light' | 'dark'`, `apiBase: string`. 메서드: `setTheme(t)`.

<details><summary>정답 보기</summary>

```ts
export class ConfigService {
  private static instance: ConfigService
  theme: 'light' | 'dark' = 'light'
  apiBase = 'https://api.example.com'

  private constructor() {}

  static getInstance() {
    if (!ConfigService.instance) ConfigService.instance = new ConfigService()
    return ConfigService.instance
  }

  setTheme(t: 'light' | 'dark') {
    this.theme = t
  }
}
```
`private constructor` 때문에 밖에서 `new` 못 함 → 오직 `getInstance()`로만 접근.
</details>

---

## Step 2 — 게으른 버전: 모듈 스코프 인스턴스

✍️ **직접 해보기**
- 위 보일러플레이트(static instance/getInstance/private) 없이, 모듈 끝에서
  인스턴스 하나만 export 해본다. 왜 이걸로 충분할까?

<details><summary>정답 보기</summary>

```ts
class ConfigServiceImpl {
  theme: 'light' | 'dark' = 'light'
  apiBase = 'https://api.example.com'
  setTheme(t: 'light' | 'dark') { this.theme = t }
}

// 모듈은 최초 import 때 한 번만 평가되고 캐시된다 → 이 인스턴스가 곧 싱글턴.
export const config = new ConfigServiceImpl()
```
`config`를 import하는 모든 파일이 같은 객체를 공유한다. getInstance가 필요 없다.
</details>

---

## Step 3 — 정체성 증명

✍️ **직접 해보기** — `Demo.tsx`
- `config`를 두 번 import(혹은 두 곳에서 참조)해서 `a === b`가 `true`인지 화면에 출력.
- 클래식 버전도 `ConfigService.getInstance() === ConfigService.getInstance()` 확인.

<details><summary>정답 보기</summary>

```tsx
import { config } from './configService'

const a = config
const b = config
// a === b 는 true — 같은 인스턴스
```
</details>

---

## Step 4 — React에서 써보기 + 함정

✍️ **직접 해보기** — `Demo.tsx`
- 버튼으로 `config.setTheme('dark')` 호출하고 `config.theme`을 표시.
- ⚠️ 눌러도 화면이 안 바뀔 것이다. **왜?** NOTES의 안티패턴에 답을 적기.
- (선택) `useState`로 강제 리렌더를 걸어 값이 실제로 바뀌었는지 확인.

<details><summary>정답 보기</summary>

싱글턴 필드를 바꿔도 React는 모른다(구독이 없으니까). 리렌더가 안 일어남.
→ 반응형이 필요하면 Day 1의 Observer(구독)나 Context와 결합해야 한다.
이게 "싱글턴은 상태 공유, 리렌더는 별개"라는 핵심 교훈.

```tsx
const [, force] = useState(0)
<button onClick={() => { config.setTheme('dark'); force(n => n + 1) }}>dark</button>
<p>theme: {config.theme}</p>
```
</details>

---

## 체크포인트 ✅
`npm run dev` → `/singleton`
- [v] `a === b` 가 true로 표시됨
- [v] setTheme 후 (강제 리렌더로) theme 값이 바뀜
- [v] "왜 그냥 눌렀을 땐 안 바뀌나"를 설명할 수 있음

## 도전 과제
1. `config`를 객체 리터럴(`export const config = { theme, setTheme }`)로 바꿔보고 클래스와 비교.
2. 싱글턴의 단점 재현: 테스트처럼 `config.theme`을 바꾼 뒤 "초기화"가 필요한 상황을 만들고 `reset()` 추가.
3. 싱글턴 + Observer 결합: `config` 변경 시 구독자에게 알리도록 만들어 리렌더까지 되게 하기.
