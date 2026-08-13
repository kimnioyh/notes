# @CreationTimestamp의 함정 (완료 시각엔 부적합)

**한 문장**: `@CreationTimestamp`는 엔티티가 **최초 persist되는 순간**의 시각을 박고 보통 `@Column(updatable = false)`와 함께라, "생성 완료 시각"처럼 **나중에 갱신돼야 하는 시각**이나 **행을 재사용하는 경우**엔 옛 값에 고정돼 맞지 않는다.

## 왜 헷갈렸나
리포트 `generatedAt`을 `@CreationTimestamp`로 뒀는데, 리포트는 GENERATING으로 먼저 저장되고 나중에 GENERATED로 채워진다. `@CreationTimestamp`는 **GENERATING 저장 시점**(=생성 시작)을 박아, "생성 완료 시각"이라는 계약과 어긋났다. 게다가 FAILED 후 같은 행을 재사용해 재생성해도 시각이 최초 값에 갇힌다.

## 핵심

### 1. @CreationTimestamp = 최초 INSERT 시각, 이후 불변
- persist 시점에 Hibernate가 현재 시각을 자동 세팅.
- 관례적으로 `@Column(updatable = false)`와 같이 써서 이후 UPDATE로도 안 바뀐다.
- 그래서 "만들어진 시각"엔 맞지만, **"완료된 시각"·"마지막 처리 시각"**엔 부적합.

### 2. 문제 상황 두 가지
- **완료 시각 표현 불가**: GENERATING(시작)에 시각이 박히므로, 완료(GENERATED) 시각을 담을 수 없다.
- **행 재사용 시 옛 값**: 같은 행을 재사용(FAILED→재생성)하면 최초 시각 그대로라, 재생성이 성공해도 응답의 시각이 낡아 사용자가 오래된 결과로 오해한다.

### 3. 해결 — 완료 시점에 수동 세팅
`@CreationTimestamp`·`updatable=false`를 떼고 **일반 필드**로 두고, 작업이 완료되는 코드에서 직접 `setGeneratedAt(Instant.now())`를 호출한다. (또는 시작 시각이 따로 필요하면 `createdAt`과 `completedAt`을 분리)

## 예시 코드
Pulse `Report` — 워커가 완료 시점에 시각을 기록:
```java
// 엔티티: 자동 타임스탬프 제거, 워커가 채운다
private Instant generatedAt;   // @CreationTimestamp 없음

// 워커(ReportFiller.fill): 집계·요약을 다 채운 뒤
report.setStatus(ReportStatus.GENERATED);
report.setGeneratedAt(Instant.now());   // "완료" 시각
```

## 확인 문제
1. `generatedAt`을 `@CreationTimestamp`로 두면 왜 "생성 완료 시각"으로 못 쓰나? 두 가지 문제 상황은?

<details><summary>답</summary>

`@CreationTimestamp`는 최초 persist(여기선 GENERATING=생성 시작) 시각을 박고 `updatable=false`라 이후 안 바뀐다. 그래서 (1) 나중에 GENERATED로 완료되는 시각을 담을 수 없고, (2) FAILED 후 같은 행을 재사용해 재생성하면 시각이 최초 값에 갇혀 성공해도 응답이 옛 시각을 보여준다. 해결은 자동 타임스탬프를 떼고 완료 코드에서 `setGeneratedAt(Instant.now())`로 수동 기록하는 것.

</details>

## 더 볼 것
- [[hibernate-json-column]] — 같은 Report 엔티티에서 만난 다른 매핑 이슈
- [[spring-async-and-completablefuture]] — 완료 시각을 세팅하는 비동기 워커
