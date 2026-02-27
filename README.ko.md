# gulf-loop

Ralph Loop 패턴에 **Human-in-the-Loop** 설계를 결합한 Claude Code 플러그인.
HCI의 실행 차(Gulf of Execution)와 평가 차(Gulf of Evaluation) 개념을 구조적 기반으로 삼는다.

---

## 개념

Donald Norman의 *『디자인과 인간 심리(The Design of Everyday Things)』*는 사람이 시스템과 상호작용할 때 발생하는 두 가지 간극을 정의한다.

**실행 차(Gulf of Execution)** — *사람이 의도한 것*과 *시스템이 제공하는 행동* 사이의 간극.
> "인증 모듈을 만들고 싶다. 그런데 이 의도를 에이전트가 실제로 올바르게 실행할 수 있는 방식으로 어떻게 전달하지?"

**평가 차(Gulf of Evaluation)** — *시스템이 만들어낸 것*과 *사람이 그게 원하던 것인지 판단할 수 있는가* 사이의 간극.
> "루프가 20번 돌고 완료됐다고 한다. 근데 실제로 맞게 된 건가?"

기존 Ralph Loop(그리고 `anthropics/ralph-wiggum`)은 루프 메커니즘이다. *지속성* 문제 — Claude가 계속 작업하게 만드는 방법 — 를 해결한다. 하지만 누가 언제 결과물을 평가하는지는 명시적으로 다루지 않는다.

**gulf-loop**는 두 간극을 모두 좁히도록 설계된 Ralph Loop 구현체다. 평가 경로에 인간을 명시적으로 배치한다.

---

## 설계 철학

```
실행 차(Gulf of Execution)           평가 차(Gulf of Evaluation)
──────────────────────               ────────────────────────────
사용자 의도 → PROMPT.md              시스템 출력 → 맞는가?
     │                                      │
     ▼                                      ▼
Phase 프레임워크                      RUBRIC.md 기준
(에이전트가 실행하는 방법)            ("완료"의 정의)
     │                                      │
     ▼                                      ▼
에이전트 반복 실행                    Judge 평가
     │                                      │
     └──────────────── HITL ───────────────┘
               Human in the loop
               (평가가 분기되는 순간)
```

**HITL 게이트**는 안전망이 아니다 — 의도된 설계다. 루프는 자동화로 해결할 수 없는 순간을 수면 위로 드러내고, 그 순간을 인간에게 넘기도록 설계되어 있다.

---

## 현재 구현된 것

### 평가 차 (충분히 커버됨)

**RUBRIC.md** — 평가 기준을 명시적이고 기계가 읽을 수 있는 형태로 정의한다.
```markdown
## Auto-checks           ← 객관적 게이트 (종료 코드)
- npm test
- npx tsc --noEmit

## Judge criteria         ← 주관적 게이트 (LLM 평가)
- 함수는 단일 책임을 갖는다.
- 에러를 조용히 처리하지 않는다.
```

**Claude Opus as judge** — 별도의 모델 인스턴스가 매 반복마다 루브릭을 기준으로 평가한다. 작업 에이전트와 평가자는 분리되어 있다.

**JUDGE_FEEDBACK.md** — 모든 거절은 타임스탬프와 이유와 함께 디스크에 기록된다. 에이전트는 이후 모든 반복의 Phase 0에서 이 파일을 읽는다. 평가 이력이 가시적이고 영속적이다.

**HITL 게이트** — N번 연속 거절 후 루프가 일시정지된다. 자동화 평가가 실패하는 순간을 드러내고, 제어권을 인간에게 돌린다: 루브릭을 업데이트하거나, 기준을 다듬거나, 에이전트 방향을 재설정한다.

```
반복 N:   REJECTED — "validateEmail이 빈 문자열을 처리하지 않음"
반복 N+1: REJECTED — "createUser에 조용한 catch 블록 있음"
반복 N+2: REJECTED — "여전히 조용한 catch 블록"
...
반복 N+4: → HITL 일시정지
               사람이 JUDGE_FEEDBACK.md 검토
               사람이 RUBRIC.md 업데이트 또는 에이전트 방향 재설정
               /gulf-loop:resume
```

### 실행 차 (부분적으로 커버됨)

**Phase 프레임워크** — 에이전트가 실행하는 방식을 구조화하기 위해 매 반복에 주입된다:
```
Phase 0:    행동 전 방향 파악 (git log, 테스트, progress.txt)
Phase 1–4:  반복당 원자적 단위 하나, 검증, 커밋
Phase 999+: 위반할 수 없는 불변 규칙
```

**언어 트리거** — 프레임워크 프롬프트에 내장된다:

| 트리거 | 효과 |
|--------|------|
| `study` the file | 행동 전 더 깊은 분석 |
| `DO NOT ASSUME not implemented` | 기존 코드 재구현 방지 |
| `capture the why` | 코드가 아닌 이유를 문서화 |
| `Ultrathink` | 복잡한 설계 결정을 위한 확장 추론 |

**부정 행위 방지 규칙** — 매 반복 주입:
```
NEVER modify, delete, or skip existing tests
NEVER hard-code values for specific test inputs
NEVER output placeholders or stubs
```

---

## 아직 구현되지 않은 것 (실행 차 간극)

실행 차에는 구조적 간극이 있다: 현재 **루프 시작 전 정렬(alignment) 단계가 없다**.

사용자가 PROMPT를 작성한다. 루프가 시작된다. 에이전트가 의도를 올바르게 해석했는지 확인하는 명시적 단계 없이 20번의 반복이 실행된다.

### 예정: `/gulf-loop:align`

루프 시작 전, 에이전트가 PROMPT를 읽고 실행 계획을 사람에게 제시하여 확인을 받는 명령어.

```bash
/gulf-loop:align "$(cat PROMPT.md)"
# 에이전트 출력:
# "목표를 다음과 같이 이해했습니다: [재진술]
#  실행 계획: [단계별 분해]
#  가정하고 있는 것들: [목록]
#  루프를 시작하려면 확인해주세요. 또는 이해를 수정해주세요."
```

이렇게 하면 비용 문제가 되기 전에 실행 차를 닫을 수 있다.

### 예정: `milestone_every` — 선제적 HITL 체크포인트

현재 HITL 게이트는 **반응적**이다 — 평가가 N번 실패한 후에만 트리거된다.

선제적 체크포인트는 judge 결과와 무관하게 일정 간격으로 루프를 일시정지하고 사람이 평가할 수 있게 한다.

```yaml
---
active: true
iteration: 7
milestone_every: 5        # 5번마다 사람 검토를 위해 일시정지
---
```

5번, 10번, 15번 반복 시: 루프 일시정지 → 진행 요약 표시 → `/gulf-loop:resume` 대기.

### 예정: `EXECUTION_LOG.md`

에이전트가 매 반복 후 남은 실행 간극에 대한 이해를 기록하는 컨벤션:
```markdown
## 반복 4
완료: 사용자 생성 엔드포인트, 입력 유효성 검사
남은 것: 비밀번호 해싱 (아직 시작 안 함), 엣지 케이스 테스트
발견한 간극: bcrypt와 argon2 중 어느 것을 사용할지 불분명 — 명세 필요
```

HITL 일시정지 순간뿐만 아니라 반복 전체에서 실행 간극을 사람에게 가시적으로 보여준다.

---

## 설치

```bash
git clone https://github.com/subinium/gulf-loop
cd gulf-loop
./install.sh
```

설치 후 Claude Code를 재시작한다.

```bash
./install.sh --uninstall   # 완전히 제거
```

**요구사항**: Claude Code ≥ 1.0.33, `jq`

---

## 사용법

### 기본 모드

완료 조건 = 에이전트가 `<promise>COMPLETE</promise>` 출력.

```bash
/gulf-loop:start "$(cat PROMPT.md)" --max-iterations 30
```

프로젝트에 `.claude/autochecks.sh`를 추가할 수 있다. 파일이 존재하고 실행 권한이 있으면, 완료 신호 감지 후 이 스크립트를 실행한다. 실패 시 완료를 거절하고 실패 출력과 함께 에이전트를 재주입한다.

```bash
# .claude/autochecks.sh
#!/usr/bin/env bash
npm test
npx tsc --noEmit
npm run lint
```

### Judge 모드 (평가 차 완전 활성화)

완료 조건 = auto-checks 통과 **AND** Opus judge 승인.

먼저 `RUBRIC.md`를 만든다(`RUBRIC.example.md` 참고), 그다음:

```bash
/gulf-loop:start-with-judge "$(cat PROMPT.md)" \
  --max-iterations 30 \
  --hitl-threshold 5
```

### 명령어

| 명령어 | 설명 |
|--------|------|
| `/gulf-loop:start PROMPT [--max-iterations N] [--completion-promise TEXT]` | 기본 루프 |
| `/gulf-loop:start-with-judge PROMPT [--max-iterations N] [--hitl-threshold N]` | Judge 포함 루프 |
| `/gulf-loop:status` | 현재 반복 횟수 확인 |
| `/gulf-loop:cancel` | 루프 중단 |
| `/gulf-loop:resume` | HITL 일시정지 후 재개 |

---

## Stop hook 흐름

### 기본 모드
```
Stop 이벤트
  ├── 상태 파일 없음 → 종료 허용
  ├── iteration >= max_iterations → 종료
  ├── 마지막 메시지에 <promise>COMPLETE</promise>
  │     .claude/autochecks.sh 존재? → 실행
  │       통과 → 종료
  │       실패 → 실패 출력과 함께 재주입
  │     autochecks.sh 없음 → 종료
  └── 그 외 → 반복 증가, 프롬프트 + 프레임워크 재주입
```

### Judge 모드
```
Stop 이벤트
  ├── [게이트 1] RUBRIC.md ## Auto-checks 실행
  │     실패 → 실패 내용과 함께 재주입
  │     모두 통과 ↓
  ├── [게이트 2] Claude Opus가 RUBRIC.md ## Judge criteria 평가
  │     APPROVED → 종료
  │     REJECTED → JUDGE_FEEDBACK.md 기록, 이유와 함께 재주입
  │     N번 연속 거절 → HITL 일시정지 (active: false)
```

---

## PROMPT.md 템플릿

```markdown
## Goal
[한 문단: 결과물이 무엇인가?]

## Current State
[파일/명령어를 가리킨다 — 에이전트가 매 반복 이것을 다시 읽는다.
상태는 임베드하지 말고 발견 가능하게 만든다.]

## Acceptance Criteria
- [ ] npm test가 종료 코드 0 반환
- [ ] TypeScript 오류 없음 (tsc --noEmit)
- [ ] ESLint 클린

## Phase 0 — Orient
- 실행: git log --oneline -10
- 실행: npm test
- 확인: progress.txt

## Phase 1–4 — Execute
1. 다음 미완료 작업 선택
2. 먼저 검색 — DO NOT ASSUME NOT IMPLEMENTED
3. 완전히 구현 — NO PLACEHOLDERS
4. 실행: npm test && npm run lint && npx tsc --noEmit
5. 모두 통과 시: git commit -m "feat: [작업]"
6. progress.txt에 추가

## Phase 999 — Invariants
999. 기존 테스트를 수정, 삭제, 건너뛰지 말 것
999. 값을 하드코딩하지 말 것
999. 플레이스홀더를 구현하지 말 것

위의 모든 인수 기준이 통과될 때만 <promise>COMPLETE</promise>를 출력할 것.
```

---

## RUBRIC.md 템플릿

```markdown
---
model: claude-opus-4-6
hitl_threshold: 5
---

## Auto-checks
- npm test
- npx tsc --noEmit
- npm run lint

## Judge criteria
- 모든 함수는 단일하고 명확한 책임을 갖는다.
- 에러 처리는 명시적이다 — 조용한 실패나 빈 catch 블록이 없다.
- 하드코딩된 시크릿, URL, 환경별 값이 없다.
- 플레이스홀더 코드가 없다: TODO 없음, 스텁 구현 없음.
- 엣지 케이스(null, 빈 값, 경계값)가 명시적으로 처리된다.
```

---

## 기존 Ralph Loop 구현과의 비교

### vs `anthropics/ralph-wiggum`

동일한 Stop hook 아키텍처. gulf-loop가 추가한 것:

| | ralph-wiggum | gulf-loop |
|---|---|---|
| 설계 프레이밍 | 루프 메커니즘 | HCI gulf 인식 루프 |
| 실행 차 | 최소 | Phase 프레임워크 + 언어 트리거를 매 반복 주입 |
| 평가 차 | 완료 약속만 | RUBRIC.md + Opus judge + JUDGE_FEEDBACK.md |
| HITL | 없음 | 핵심 설계 — 평가 분기 시 선제적 일시정지 |
| 완료 감지 | JSONL 트랜스크립트 파싱 | `last_assistant_message` 필드 직접 사용 |

### vs `snarktank/ralph` (외부 bash 루프)

다른 아키텍처. 외부 루프 = 반복마다 완전히 새로운 컨텍스트. Stop hook 루프 = 동일 세션 유지.

| | snarktank/ralph | gulf-loop |
|---|---|---|
| 반복당 컨텍스트 | 완전 초기화 | 누적 |
| 적합한 경우 | 100번 이상 반복 | 50번 이하 반복 |
| Gulf 인식 | 설계 목표 아님 | 핵심 설계 목표 |

---

## 참고문헌

- Norman, D. A. (1988). *The Design of Everyday Things*. — 실행 차와 평가 차
- [ghuntley.com/ralph](https://ghuntley.com/ralph) — Geoffrey Huntley, Ralph Loop 기법 창시자
- [anthropics/claude-code plugins/ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) — 공식 Stop hook 플러그인
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks) — Stop hook 레퍼런스
