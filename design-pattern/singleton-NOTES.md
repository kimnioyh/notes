# Singleton

## 한 문장
어떤 것의 인스턴스를 앱 전체에서 **딱 하나만** 두고, 어디서 접근해도 같은 인스턴스를 돌려준다.

## 왜 필요한가
설정(config), 로거, API 클라이언트, 캐시처럼 "여러 개 생기면 곤란한" 것들.
컴포넌트마다 `new ConfigService()`를 하면 각자 다른 상태를 들고 따로 논다.

## 세 가지 구현 방식 (덜 → 더 게으름)
1. **클래식 GoF**: private 생성자 + `static getInstance()` — 자바/C++식.
2. **모듈 스코프 인스턴스** ✅ : `export const config = new ConfigService()`
   - JS 모듈은 처음 import될 때 한 번만 실행되고 캐시된다 → **모듈 자체가 이미 싱글턴**.
   - 그래서 대부분 `getInstance()` 보일러플레이트가 불필요하다.
3. **그냥 객체 리터럴**: 클래스도 필요 없으면 `export const config = { ... }`.

## React 실전 앵커
- `services/config.ts`, `services/apiClient.ts` 처럼 모듈에서 인스턴스 하나 export.
- Day 1의 `toastStore`도 사실 이 패턴(모듈 스코프 싱글턴)이었다.

## 핵심: 정체성(identity)
싱글턴인지 확인하는 법 = 서로 다른 곳에서 가져온 참조가 `===` 로 같은가.

## 언제 쓰나
- 전역 설정/로거/클라이언트 등 상태나 연결을 공유해야 할 때.

## 안티패턴 / 조심
- **숨은 전역 상태**: 싱글턴은 결국 전역 변수. 테스트 시 상태가 남아 서로 오염됨(테스트마다 reset 필요).
- 리액트에서 싱글턴 상태를 바꿔도 **자동 리렌더 안 됨** → 반응형이 필요하면 Observer/Context와 결합해야 한다.
- getInstance 보일러플레이트를 굳이 쓰지 말 것. 모듈 export로 충분.
