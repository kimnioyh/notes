# auth 인식 다형 응답 (같은 URL, 인증 여부로 다른 스키마)

**한 문장**: 하나의 공개 `GET`이 **인증 여부에 따라 다른 타입**을 반환하려면(소유자=전체 뷰 / 게스트=공개 뷰), 컨트롤러가 `@AuthenticationPrincipal(errorOnInvalidType = false)`로 **게스트를 null로 받고** 서비스가 그 null 여부로 분기한다.

## 왜 헷갈렸나
`GET /report`는 공개(permitAll)인데 소유자에겐 전체(`Report`), 게스트에겐 공개분(`PublicReport`)을 줘야 했다. "같은 엔드포인트가 어떻게 인증 여부를 알고 다른 걸 주지?"와 "게스트는 principal이 없는데 `@AuthenticationPrincipal Long`이 어떻게 되지?"가 안 잡혔다.

## 핵심

### 1. errorOnInvalidType = false → 게스트는 null
공개 엔드포인트는 게스트도 들어온다. 게스트는 SecurityContext의 principal이 우리 `Long`(유저 id)이 아니라 익명 토큰이다.
- 기본값이면 타입이 안 맞아 **예외**가 난다.
- `@AuthenticationPrincipal(errorOnInvalidType = false) Long userId`로 두면 **못 맞출 때 예외 대신 null**을 넣어준다.
→ 그래서 "미인증 = null"로 다룰 수 있고, 그걸로 소유자/게스트를 가른다.

### 2. 반환 타입은 다형(Object) → 서비스가 분기
```java
public Object getReport(String eventCode, Long ownerId) {  // 반환 다형
    Report report = ...orElseThrow(REPORT_NOT_FOUND);
    boolean isOwner = ownerId != null && report.getEvent().getOwner().getId().equals(ownerId);
    if (isOwner)            return ReportResponse.from(report);  // 전체
    if (report.isPublic())  return PublicReport.from(report);    // 공개분
    throw new ApiException(REPORT_NOT_FOUND);                    // 비공개는 숨김
}
```
컨트롤러는 `ResponseEntity<?>`로 감싸 그대로 내보낸다. (openapi에선 `anyOf: [Report, PublicReport]`로 문서화)

### 3. 비공개는 404로 "숨긴다"
게스트에게 비공개 리포트는 "권한 없음(403)"이 아니라 **존재 자체를 안 알리는 404**(`REPORT_NOT_FOUND`)로 응답한다. 리소스 존재를 노출하지 않는 흔한 패턴(삭제된 이벤트를 공개 조회에서 404로 숨긴 것과 같은 결).

## 예시 코드
Pulse `ReportController` — 공개지만 인증되면 전체 뷰:
```java
@Operation(security = {})   // 공개 표시
@GetMapping
public ResponseEntity<?> get(
        @AuthenticationPrincipal(errorOnInvalidType = false) Long userId,  // 게스트면 null
        @PathVariable String eventCode) {
    return ResponseEntity.ok(reportService.getReport(eventCode, userId));
}
```

## 확인 문제
1. 공개 `GET`에 `@AuthenticationPrincipal Long userId`를 그냥 쓰면 게스트 요청에 무슨 일이 나나? `errorOnInvalidType = false`는 뭘 해주나?
2. 게스트에게 비공개 리포트를 403이 아니라 404로 응답하는 이유는?

<details><summary>답</summary>

1. 게스트의 principal은 우리 `Long`이 아니라 익명 토큰이라, 기본값이면 타입 불일치 예외가 난다. `errorOnInvalidType = false`는 못 맞출 때 예외 대신 null을 넣어줘서 "미인증=null"로 다뤄 소유자/게스트를 분기할 수 있게 한다.

2. 403은 "리소스가 있고 너는 권한이 없다"라 존재를 노출한다. 비공개 리포트는 게스트에게 존재 자체를 안 알리는 게 낫기 때문에 404(없는 것처럼)로 숨긴다.

</details>

## 더 볼 것
- [[spring-mvc-param-binding]] — @AuthenticationPrincipal로 유저 id를 꺼내는 흐름
- [[spring-security-cookie-csrf]] — 쿠키 JWT가 SecurityContext principal을 채우는 배경
