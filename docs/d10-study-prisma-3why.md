# D10 스터디 — Prisma 3-why 오너십 워크북

> 목표: `apps/dashboard/lib/prisma.ts`를 **Claude/주석 없이** 방어. base 답은 네 주석에 있음.
> 진짜 시험은 **킬러 후속질문**. 여기서 안 흔들리면 Prisma는 "제일 안 내꺼" → "제일 빈틈없는 카드".
> 규칙: 빈칸은 본인이 채운다. 막히면 채우지 말고 "여기서 막혔다"고 표시 → 그 지점만 같이 판다.

---

## Why 1 — 왜 driver adapter인가? (Prisma 7)

**base 답 (한 줄):**
> [ TODO ]

**킬러 후속:**
- Q. Prisma 6까지는 어떻게 연결했는데, 7에서 왜 굳이 adapter로 바꿨나? (힌트: 쿼리 엔진이 어디서 돌았나 → 서버리스/엣지에서 뭐가 문제였나)
> [ TODO ]
- Q. adapter가 없으면 이 프로젝트(Vercel 서버리스)에서 구체적으로 뭐가 안 되나?
> [ TODO ]

---

## Why 2 — 왜 싱글톤인가? (globalThis 캐싱)

**base 답 (한 줄):**
> [ TODO ]

**킬러 후속:**
- Q. 싱글톤 안 하면 *정확히* 어떤 에러/증상이 나나? (에러 메시지 형태까지 말할 수 있으면 만점)
> [ TODO ]
- Q. 13번 줄은 왜 `production`에서는 globalThis에 안 담나? (프로덕션은 왜 그냥 new 해도 괜찮은가)
> [ TODO ]

---

## Why 3 — 왜 SQLite → Neon Postgres인가?

**base 답 (한 줄):**
> [ TODO ]

**킬러 후속:**
- Q. Vercel 서버리스에서 SQLite 파일이 왜 안 되나? (힌트: 람다 파일시스템의 두 가지 성질)
> [ TODO ]
- Q. 그냥 일반 Postgres(RDS 등) 두고 왜 하필 Neon인가? 서버리스에서 Neon이 푸는 문제는?
> [ TODO ]

---

## 오너십 시험 (마지막 관문)

Claude/주석/이 파일 다 덮고:
1. `lib/prisma.ts` 13줄을 백지에 다시 써봐라. 안 보고.
2. 위 6개 후속질문을 소리 내어 답해라. (녹음해서 들어보면 어디서 버벅이는지 바로 나옴)

→ 통과하면 job-narrative의 오너십 헤드라인에서 Prisma 구멍 하나 메움. 다음: 서버/클라 경계.
