# 자바 기본형 vs 래퍼 클래스 (long vs Long)

**한 문장**: `null`이 의미가 있으면 래퍼(`Long`), 값이 항상 있으면 기본형(`long`)을 쓴다.

## 왜 헷갈렸나
Pulse 코드에서 어떤 데는 `long`(`TokenResponse.expiresIn`), 어떤 데는 `Long`(엔티티 `id`)을 써서 기준이 안 잡혔다. "그냥 숫자인데 왜 둘로 나뉘지?"가 안 풀렸다. 핵심은 **null을 담을 수 있느냐**였다.

## 핵심

### 래퍼 가족
| 기본형 | 래퍼 | 기본형 | 래퍼 |
|--------|------|--------|------|
| `int` | `Integer` | `boolean` | `Boolean` |
| `long` | `Long` | `double` | `Double` |
| `char` | `Character` | `byte` | `Byte` |

기본형을 **객체로 감싼 것**이 래퍼다.

| | `long` (기본형) | `Long` (래퍼) |
|---|---|---|
| null | ❌ 불가 (기본값 `0`) | ✅ 가능 (= "값 없음") |
| 정체 | 순수 값 | 값을 감싼 **객체** |
| 제네릭 | ❌ `List<long>` 불가 | ✅ `List<Long>` 가능 |

### 래퍼(`Long`)를 쓰는 경우 — null이 필요할 때
1. **JPA 엔티티 `@Id`** → 저장 전엔 id가 아직 없음(null), DB가 채워줌. 기본형이면 null을 못 담아 0으로 오해됨.
2. **nullable 컬럼 / 선택적 값** (있을 수도 없을 수도)
3. **제네릭 타입 인자** → `List<Long>`, `Optional<Long>`, `Map<String, Long>`. 제네릭엔 기본형을 못 쓴다.

### 기본형(`long`)을 쓰는 경우 — 항상 값이 있을 때
1. 계산용 지역변수, 카운트, 합계
2. 절대 null일 리 없는 필드 (예: 토큰 유효시간, 공개여부 boolean)

## 예시 코드
Pulse에서 실제로 마주친 자리들:

```java
// ① 엔티티 PK → Long (저장 전 null, DB가 채움)
@Id @GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;

// ② 항상 존재하는 값 → long
public record TokenResponse(String accessToken, long expiresIn) {}

// ③ 제네릭엔 무조건 래퍼
Optional<User> findByEmail(String email);   // UserRepository
List<String> keywords;                       // Feedback.keywords

// ④ null 가능성을 타입으로 강제 → Optional (로그인 검증)
User u = userRepository.findByEmail(email)
        .orElseThrow(() -> new BadCredentialsException("존재하지 않는 사용자"));

// ⑤ 래퍼 클래스의 static 파싱 유틸
Long.parseLong(sub);       // JwtProvider.parseUserId — String "42" → long
Integer.parseInt("3");
Boolean.parseBoolean("true");

// ⑥ 항상 true/false → 기본형 boolean (null 아님)
private boolean toxic;      // Feedback
private boolean isPublic;   // Report
```

> `Long.parseLong`은 기본형 `long`을 반환하고, `Long.valueOf`는 래퍼 `Long`을 반환한다. 미묘하지만 다르다.

## ⚠️ 함정 두 가지

### 1. null 언박싱 → NPE
`null`인 래퍼를 기본형에 넣으면 자동 언박싱되다가 터진다.
```java
Long maybe = null;
long x = maybe;   // 💥 NullPointerException
```
→ null 가능성 있으면 래퍼로 들고 다니다가, 쓸 때 null 체크.

### 2. 래퍼 `==` 는 값이 아니라 참조 비교
```java
Long a = 1000L, b = 1000L;
a == b        // ❌ false (다른 객체)
a.equals(b)   // ✅ true  (값 비교)
```
게다가 `-128~127`은 캐싱돼서 `==`가 우연히 true가 나오기도 해 더 헷갈린다. **래퍼 값 비교는 항상 `.equals()`** (또는 기본형으로 풀어서).

## 확인 문제
1. JPA 엔티티의 `@Id`를 `long`이 아니라 `Long`으로 두는 이유는?
2. `Long a = 1000L, b = 1000L;`에서 `a == b`가 `false`인 이유와, 값을 제대로 비교하려면?

<details><summary>답</summary>

1. 엔티티를 저장하기 **전에는 id가 아직 없어서(null)**, DB가 채워줄 때까지 "값 없음"을 표현해야 한다. 기본형 `long`은 null을 못 담아 자동으로 `0`이 되어 "id가 0인 행"과 구분이 안 된다. 그래서 null을 담을 수 있는 래퍼 `Long`을 쓴다.
2. `Long`은 **객체**라 `==`는 값이 아니라 "같은 객체 참조냐"를 비교한다. `1000`은 Integer/Long 캐시 범위(`-128~127`) 밖이라 서로 다른 객체 → `false`. 값 비교는 `a.equals(b)`를 쓰거나 기본형 `long`으로 언박싱해서 비교한다.

</details>

## 더 볼 것
- [[java-01-basics]] — 자바 기본 개념
- 오토박싱/언박싱, `Integer` 캐시(`-128~127`), `Optional` 활용
