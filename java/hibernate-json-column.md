# Hibernate JSON 컬럼 매핑 (@JdbcTypeCode(SqlTypes.JSON))

**한 문장**: 값 객체나 리스트를 별도 테이블 없이 통째로 저장하려면 엔티티 필드에 `@JdbcTypeCode(SqlTypes.JSON)`을 붙이면 Hibernate 6가 그 필드를 JSON으로 직렬화해 **dialect별 JSON 컬럼**(Postgres `jsonb`, H2 `json`)에 넣고, 조회 시 역직렬화해준다.

## 왜 헷갈렸나
리포트의 감정 분포(`SentimentBreakdown`)·키워드 목록(`List<KeywordCount>`)을 어떻게 저장할지 막혔다. 별도 테이블로 정규화하자니 조회 전용 집계라 과하고, `String`에 수동 JSON 조립은 지저분했다. 답은 Hibernate가 JSON 컬럼 매핑을 직접 지원한다는 것.

## 핵심

### 1. @JdbcTypeCode(SqlTypes.JSON) — 필드를 JSON 컬럼으로
```java
@JdbcTypeCode(SqlTypes.JSON)
private SentimentBreakdown sentimentBreakdown;   // record/POJO

@JdbcTypeCode(SqlTypes.JSON)
private List<KeywordCount> topKeywords;           // 리스트도 통째로
```
- 저장 시 Jackson으로 직렬화, 조회 시 역직렬화. 별도 매핑 코드 불필요.
- 조회 전용 집계처럼 "통째로 넣고 통째로 읽는" 데이터에 적합(정규화 오버엔지니어링 회피).

### 2. columnDefinition은 생략 → 이식성
`@Column(columnDefinition = "jsonb")`처럼 타입을 하드코딩하면 **H2는 `jsonb`를 몰라 DDL이 깨진다**(로컬 테스트 실패). `@JdbcTypeCode(JSON)`만 두면 Hibernate가 **dialect별로 알맞은 타입**(Postgres `jsonb`, H2 `json`)을 생성해 로컬↔배포 이식성이 유지된다.

### 3. round-trip은 반드시 실제로 검증
JSON 매핑은 "저장(DDL·직렬화)"만 되고 "조회(역직렬화)"에서 깨질 수 있다. persist 성공만으로는 부족하니, **저장 → flush/clear → 다시 find → 값 비교**까지 하는 테스트로 라운드트립을 확인해야 한다.

## 예시 코드
Pulse `Report` 엔티티 + 라운드트립 테스트:
```java
@JdbcTypeCode(SqlTypes.JSON) private SentimentBreakdown sentimentBreakdown;
@JdbcTypeCode(SqlTypes.JSON) private List<KeywordCount> topKeywords;
```
```java
report = new Report(event, "요약", new SentimentBreakdown(5,3,2), 1, List.of(new KeywordCount("발표속도",7)), true);
em.persist(report); em.flush(); em.clear();
Report found = em.find(Report.class, report.getId());
assertThat(found.getSentimentBreakdown().POS()).isEqualTo(5);       // 역직렬화 확인
assertThat(found.getTopKeywords().get(0).count()).isEqualTo(7);
```

## 확인 문제
1. `@Column(columnDefinition = "jsonb")`를 붙이면 로컬(H2) 테스트에서 왜 깨질 수 있나? `@JdbcTypeCode(JSON)`만 두면 어떻게 되나?
2. JSON 컬럼 매핑에서 persist 성공만으로 충분하지 않은 이유는?

<details><summary>답</summary>

1. `jsonb`는 Postgres 타입이라 H2가 몰라 DDL 생성이 실패한다. `@JdbcTypeCode(SqlTypes.JSON)`만 두면 Hibernate가 dialect별로 알맞은 JSON 타입(Postgres jsonb, H2 json)을 스스로 생성해 이식성이 유지된다.

2. 저장은 됐어도 조회 시 JSON을 객체로 역직렬화하는 단계에서 깨질 수 있다. 저장→flush/clear→재조회→값 비교까지 하는 라운드트립 테스트로 역직렬화까지 확인해야 한다.

</details>

## 더 볼 것
- [[jpa-association-mapping]] — @ElementCollection(별도 테이블) vs JSON 컬럼(통째 저장)의 선택
- [[creationtimestamp-pitfall]] — 같은 Report 엔티티에서 만난 다른 매핑 함정
