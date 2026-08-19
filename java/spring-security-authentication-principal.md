# @AuthenticationPrincipal은 UserDetails 없이도 동작한다

**한 문장**: `@AuthenticationPrincipal`은 `SecurityContext`에 담긴 `Authentication`의 **principal 필드를 꺼내주는 도구일 뿐**이고, principal이 `UserDetails`여야 한다는 규약은 없다 — 우리는 JWT 필터에서 principal 자리에 `userId`(Long)를 직접 넣어 그 Long을 컨트롤러에서 받는다.

## 왜 헷갈렸나

시큐리티 강의는 대부분 **폼 로그인 + `UserDetailsService` + `UserDetails` 구현**을 가르친다. 그래서 이런 의문이 생긴다:

> "`UserDetails`를 implements 안 해도 되나? 컨트롤러에서 `@AuthenticationPrincipal`을 쓰려면 시큐리티에 우리 유저 정보를 등록해야 하는 거 아냐?"

답은 **아니다.** `UserDetails`는 `@AuthenticationPrincipal`이 요구하는 게 아니라, *스프링의 기본 인증 경로(`DaoAuthenticationProvider`)를 쓸 때* 딸려오는 규약이다. 그 경로를 안 쓰면 `UserDetails`도, `UserDetailsService`도 필요 없다.

## 핵심

### 1. `@AuthenticationPrincipal`이 실제로 하는 일

마법이 아니라 아래 한 줄의 축약이다:

```java
SecurityContextHolder.getContext().getAuthentication().getPrincipal()
```

`Authentication` 객체의 **principal 필드를 그대로 꺼내** 컨트롤러 파라미터에 바인딩한다. principal의 **타입은 무엇이든 상관없다** — `UserDetails`든, 커스텀 객체든, 그냥 `Long`이든. 우리가 넣은 타입이 그대로 나온다.

```java
// principal에 Long을 넣었으니
@GetMapping
public FeedbackListResponse list(@AuthenticationPrincipal Long userId) { ... }
//                               └ authentication.getPrincipal()을 Long으로 캐스팅해서 줌
```

### 2. principal은 누가 넣나 — `setAuthentication` 한 줄

"시큐리티에 유저 정보를 등록"한다는 건 거창한 게 아니라 필터에서 이 한 줄이다:

```java
// JwtAuthenticationFilter.doFilterInternal
Long userId = jwtProvider.parseUserId(token);        // 토큰 검증 + userId 추출
var auth = new UsernamePasswordAuthenticationToken(
        userId,        // 1번 인자 = principal  ← @AuthenticationPrincipal로 나오는 값
        null,          // 2번 = credentials (검증 끝났으니 비번 버림)
        List.of());    // 3번 = authorities (권한/역할 — 안 쓰면 빈 리스트)
SecurityContextHolder.getContext().setAuthentication(auth);  // ← 이게 "등록"
```

- 매 요청마다 필터가 JWT를 까서 `userId` **하나만** SecurityContext에 꽂는다.
- DB 유저 전체가 아니라 **식별자만** 넣는다. 소유권 검사는 서비스에서 그 `userId`로 다시 조회.
- `UsernamePasswordAuthenticationToken`이라는 이름 때문에 "폼 로그인 전용" 같지만, 그냥 `Authentication`의 흔한 구현체일 뿐 — principal에 아무거나 담을 수 있다.

### 3. 그럼 `UserDetails` / `UserDetailsService`는 왜 있나

스프링 **기본 인증 방식(폼 로그인, HTTP Basic 등 → `AuthenticationManager` → `DaoAuthenticationProvider`)** 을 쓸 때의 산출물이다:

```
로그인 요청 → AuthenticationManager → DaoAuthenticationProvider
           → UserDetailsService.loadUserByUsername(email)   // 네가 구현
           → UserDetails 반환 → 내부에서 비번 매칭(PasswordEncoder)
           → 성공 시 principal = 그 UserDetails
```

이 경로를 타면 principal이 `UserDetails`가 되니까 `@AuthenticationPrincipal CustomUserDetails user`로 받게 된다. **강의가 가르친 게 이 시나리오.** 여기서 `UserDetails`는 "provider가 비번을 매칭할 수 있도록 유저의 해시·권한을 표준 인터페이스로 감싼 것"이다.

### 4. 우리(Pulse)가 그 경로를 안 쓰는 이유

로그인을 `AuthService.login()`에서 **직접** 처리한다 — 이메일 조회 + BCrypt 매칭 + JWT 발급. 스프링의 `AuthenticationManager`/`Provider` 체인을 **안 거친다.** 그래서:

| 기본 경로(강의) | 우리 경로(JWT) |
|---|---|
| `UserDetailsService` 등록 필요 | **불필요** (provider가 안 부름) |
| `UserDetails` 구현 필요 | **불필요** (principal을 Long으로 직접 세팅) |
| principal = `UserDetails` | principal = `Long userId` |
| 세션에 인증 저장 | stateless, 매 요청 필터가 토큰에서 재구성 |

로그인 시 검증은 우리가 하고, 그 결과를 **JWT라는 종이 도장**으로 발급한다. 이후 모든 요청은 필터가 그 도장(토큰)만 까서 `userId`를 principal에 꽂으면 끝. provider 체인이 낄 자리가 없다.

## 예시 코드

발급(로그인)과 검증(필터)이 **principal의 정체를 합의**하는 게 전부다:

```java
// 발급: AuthService → JwtProvider — 토큰 안에 userId를 subject로 심음
jwtProvider.generateAccessToken(user.getId());

// 검증: JwtAuthenticationFilter — 토큰에서 userId 꺼내 principal로
Long userId = jwtProvider.parseUserId(token);
SecurityContextHolder.getContext().setAuthentication(
        new UsernamePasswordAuthenticationToken(userId, null, List.of()));

// 소비: 아무 컨트롤러 — principal(Long)을 그대로 받음
@AuthenticationPrincipal Long userId
```

**트레이드오프**: principal을 Long으로 두면 가볍고 stateless지만, email·role이 필요하면 매번 DB를 다시 조회해야 한다. 지금 규모(소유권 = `userId` 비교)엔 이게 맞다. 나중에 role 기반 인가(`@PreAuthorize("hasRole('ADMIN')")`)가 필요해지면 그때 3번 인자(authorities)를 채우거나 principal을 커스텀 객체로 승격하면 된다 — 지금은 YAGNI.

> 게스트 허용 엔드포인트에선 principal이 없을 수 있다. `@AuthenticationPrincipal(errorOnInvalidType = false) Long userId`처럼 받아 인증 안 된 요청엔 `null`이 들어오게 하고, 서비스에서 소유자/게스트 분기를 태운다. → [[auth-aware-polymorphic-response]]

## 확인 문제

1. `@AuthenticationPrincipal Long userId`로 Long을 받을 수 있는 이유는? `UserDetails`를 구현했기 때문인가?
2. 강의에선 `UserDetailsService`를 반드시 만들라고 했는데 우리 프로젝트엔 없다. 그래도 인증이 되는 이유는?

<details><summary>답</summary>

1. `UserDetails`와 무관하다. `@AuthenticationPrincipal`은 `authentication.getPrincipal()`을 꺼내 파라미터 타입으로 주는 것뿐이고, principal의 타입은 우리가 정한다. JWT 필터에서 `new UsernamePasswordAuthenticationToken(userId, ...)`로 **principal 자리에 Long을 직접 넣었기** 때문에 Long으로 나온다.
2. `UserDetailsService`는 스프링 기본 인증 경로(`DaoAuthenticationProvider`)가 유저를 로드할 때 부르는 콜백이다. 우리는 그 경로 대신 `AuthService.login()`에서 직접 이메일 조회+BCrypt 매칭을 하고 JWT를 발급한다. provider 체인을 안 타니 `UserDetailsService`를 부를 주체 자체가 없다. 인증 상태는 매 요청 JWT 필터가 토큰을 까서 `SecurityContext`에 재구성한다.

</details>

## 더 볼 것

- [[spring-security-jwt-filter-chain]] — 필터가 언제 principal을 세팅하고 인가는 어디서 걸리나
- [[spring-security-cookie-csrf]] — 이 토큰을 HttpOnly 쿠키로 나를 때의 CSRF
- [[auth-aware-polymorphic-response]] — principal `null`(게스트) 분기로 응답 다형화
- 키워드: `Authentication`, `getPrincipal()`, `UserDetailsService`, `DaoAuthenticationProvider`, `UsernamePasswordAuthenticationToken`, stateless
