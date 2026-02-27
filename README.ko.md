# gulf-loop

Ralph Loop 패턴에 **Human-in-the-Loop** 설계를 결합한 Claude Code 플러그인.
HCI의 실행 차(Gulf of Execution)와 평가 차(Gulf of Evaluation) 개념을 구조적 기반으로 삼는다.

---

## 목차

1. [왜 이걸 만들었는가](#1-왜-이걸-만들었는가)
2. [두 개의 간극](#2-두-개의-간극)
3. [핵심 설계 원칙](#3-핵심-설계-원칙)
4. [구성 요소와 그 이유](#4-구성-요소와-그-이유)
5. [세 가지 모드와 트레이드오프](#5-세-가지-모드와-트레이드오프)
6. [자율 모드의 설계](#6-자율-모드의-설계)
7. [아직 없는 것](#7-아직-없는-것)
8. [설치](#8-설치)
9. [사용법](#9-사용법)
10. [기존 구현과의 비교](#10-기존-구현과의-비교)
11. [참고문헌](#11-참고문헌)

---

## 1. 왜 이걸 만들었는가

### Ralph Loop가 해결한 것

Ralph Loop(Ralph Wiggum 기법)는 Claude Code의 Stop 훅을 이용해 Claude가 응답을 마칠 때마다 같은 프롬프트를 재주입하는 패턴이다. 이것이 해결하는 문제는 하나다: **지속성** — 에이전트가 멈추지 않고 계속 작업하게 만드는 방법.

이 아이디어는 강력하다. 에이전트는 단일 세션에서 처리하기 어려운 큰 작업을 반복적으로 조금씩 진행할 수 있다.

### Ralph Loop가 해결하지 않은 것

그런데 실제로 써보면 한 가지 근본적인 문제가 드러난다.

**루프가 멈추는 조건이 에이전트 자신의 판단이다.**

에이전트가 `<promise>COMPLETE</promise>`를 출력하면 루프가 끝난다. 에이전트가 작업을 완료했다고 *판단*하면 종료된다. 외부에서 이것을 검증하는 메커니즘이 없다.

이 구조에서 발생하는 문제:

- 에이전트가 스텁 코드를 작성하고 완료라고 할 수 있다.
- 에이전트가 테스트를 삭제하고 완료라고 할 수 있다.
- 에이전트가 잘못된 방향으로 20번 반복한 후 완료라고 할 수 있다.
- 사람은 최종 결과물을 보기 전까지 루프 도중에 무슨 일이 일어났는지 알 수 없다.

**"계속 해"라는 루프를 만든 건데, 뭘 계속 하는지는 여전히 불투명하다.**

gulf-loop는 이 문제를 정면으로 다룬다.

---

## 2. 두 개의 간극

Donald Norman의 *『디자인과 인간 심리(The Design of Everyday Things)』*(1988)는 사람이 시스템과 상호작용할 때 생기는 두 가지 근본적인 간극을 정의한다.

### 실행 차 (Gulf of Execution)

*사람이 의도한 것*과 *시스템이 제공하는 행동* 사이의 간극.

> "인증 모듈을 만들고 싶다. 그런데 이 의도를 에이전트가 실제로 올바르게 실행할 수 있는 방식으로 어떻게 전달하지? 어느 파일을 먼저 봐야 하는지, 어떤 단위로 작업해야 하는지, 기존 코드를 얼마나 파악해야 하는지 — 이 모든 맥락이 전달되지 않으면 에이전트는 내가 원하는 방향과 다르게 움직인다."

### 평가 차 (Gulf of Evaluation)

*시스템이 만들어낸 것*과 *사람이 그게 원하던 것인지 판단할 수 있는가* 사이의 간극.

> "루프가 20번 돌고 완료됐다고 한다. 테스트는 통과한다. 그런데 이게 실제로 내가 원하던 거야? 함수들이 단일 책임을 갖고 있나? 에러를 조용히 삼키는 코드가 없나? 나중에 유지보수하기 어려운 구조로 짜인 건 아닌가?"

### AI 에이전트 맥락에서의 재해석

Norman이 1988년에 정의한 이 개념은 GUI나 물리적 도구에 대한 것이었다. gulf-loop는 이 개념을 AI 에이전트 루프에 적용한다.

에이전트 루프에서:

- **실행 차** = 사람의 의도가 에이전트의 실행 방식으로 제대로 전환되지 못하는 간극. 프롬프트에 "인증 모듈 만들어"라고 써도, 에이전트가 Phase 없이 즉흥적으로 작업하거나, 기존 코드를 확인하지 않고 재구현하거나, 한 반복에 너무 많은 것을 하려다 망가뜨리는 것.
- **평가 차** = 에이전트가 완료라고 했지만 사람이 그게 실제로 올바른지 판단하기 어려운 간극. 테스트가 통과한다고 코드가 좋은 건 아니다. "완료"와 "올바름"은 다르다.

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

---

## 3. 핵심 설계 원칙

### 원칙 1: 작업자와 평가자를 분리한다

Ralph Loop의 근본적 문제는 **작업한 에이전트가 동시에 완료를 인증한다**는 것이다.

gulf-loop judge 모드에서는 이 두 역할이 분리된다.

- **작업 에이전트**: 코드를 작성하고 `<promise>COMPLETE</promise>`를 출력한다.
- **평가 에이전트**: 별도의 Claude Opus 인스턴스가 RUBRIC.md 기준으로 독립적으로 평가한다.

작업 에이전트의 완료 선언은 평가 요청일 뿐이다. 평가자가 승인해야 실제로 완료된다.

이것은 소프트웨어 개발의 코드 리뷰 원칙과 같다: 자신이 짠 코드를 자신이 최종 승인하면 안 된다.

### 원칙 2: HITL은 안전망이 아니라 설계다

HITL(Human-in-the-Loop) 게이트는 "문제가 생겼을 때 사람이 개입한다"는 개념이 아니다.

gulf-loop에서 HITL은 **자동화 평가가 수렴하지 못하는 순간을 감지하고, 그 순간에 제어권을 인간에게 넘기는** 의도적인 설계다.

N번 연속 거절은 두 가지 중 하나를 의미한다:

1. 에이전트가 올바른 방향을 찾지 못하고 있다 — 방향 재설정이 필요하다.
2. RUBRIC.md의 기준이 현재 상황에 맞지 않는다 — 기준 업데이트가 필요하다.

둘 다 **자동화로 해결할 수 없는 판단**이다. 그래서 HITL 게이트가 트리거되는 것 자체가 정상 동작이다. 루프가 실패한 게 아니라, 루프가 자신이 해결할 수 없는 문제를 발견해서 사람에게 알린 것이다.

### 원칙 3: "완료"를 사전에 정의한다

암묵적인 완료 기준이 평가 차의 원인이다.

"잘 만들어줘"는 에이전트도 모르고 사람도 막상 결과물을 보기 전까지 모른다. 루프를 시작하기 전에 완료의 정의가 명시적이어야 한다.

RUBRIC.md는 이 정의를 두 층으로 나눈다:

- **Auto-checks**: 기계가 판단할 수 있는 객관적 기준 (테스트, 타입 체크, 린트)
- **Judge criteria**: 기계가 판단하기 어려운 주관적 기준 (단일 책임 원칙, 에러 처리 방식)

객관적 기준이 통과해야 주관적 기준 평가로 넘어간다. 순서가 있다.

### 원칙 4: 평가 이력은 영속적이어야 한다

에이전트는 반복마다 새로운 컨텍스트로 시작한다. 이전 반복에서 왜 거절됐는지 기억하지 못하면, 같은 실수를 반복한다.

JUDGE_FEEDBACK.md는 모든 거절 이유를 타임스탬프와 함께 파일에 기록한다. 에이전트는 매 반복 Phase 0에서 이 파일을 읽는다. 평가 이력이 에이전트의 작업 기억이 된다.

---

## 4. 구성 요소와 그 이유

### Phase 프레임워크 — 실행 차를 좁히는 구조

Phase 프레임워크는 매 반복 에이전트에게 주입되는 실행 구조다. 에이전트에게 "뭘 만들어"가 아니라 "어떻게 접근해"를 알려준다.

#### Phase 0: 방향 파악 (Orient)

```
git log --oneline -10
[테스트 명령어]
cat progress.txt
```

이것이 있는 이유: 에이전트는 매 반복 빈 컨텍스트로 시작한다. Phase 0 없이 바로 작업하면 이전 반복의 상태를 파악하지 못하고 이미 완료된 작업을 다시 하거나, 실패한 접근을 반복한다.

Phase 0는 컨텍스트 예산의 20% 이내로 제한한다. 너무 많이 읽으면 정작 작업할 컨텍스트가 부족해진다.

#### Phase 1–4: 원자적 실행 (Execute)

반복당 하나의 원자적 단위만 구현한다. 하나의 기능, 하나의 버그 수정, 하나의 테스트 추가.

이것이 있는 이유: 한 반복에 너무 많은 것을 하면 검증하기 어렵고, 뭔가 망가졌을 때 어디서 망가졌는지 추적하기 어렵다. 원자적 단위 + 커밋은 자연스러운 롤백 포인트를 만든다.

```
1. 검색 먼저 — DO NOT ASSUME NOT IMPLEMENTED
2. 완전히 구현 — NO PLACEHOLDERS
3. 테스트 + 린트 + 타입 체크 실행
4. 모두 통과 시 커밋
5. progress.txt 업데이트
```

#### Phase 999+: 불변 규칙 (Invariants)

```
NEVER modify, delete, or skip existing tests
NEVER hard-code values for specific test inputs
NEVER output placeholders or stubs
```

이것이 있는 이유: 에이전트는 완료 신호를 내보내기 위해 지름길을 택할 수 있다. 테스트를 삭제하면 테스트가 통과한다. 하드코딩하면 특정 케이스는 통과한다. Invariants는 이런 부정행위를 명시적으로 금지한다.

번호가 999인 이유: 이 규칙들은 어떤 상황에서도 우선순위가 가장 높다.

### RUBRIC.md — 완료의 명시적 정의

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
```

Auto-checks는 종료 코드로 판단한다. 0이면 통과, 아니면 실패. 모호함이 없다.

Judge criteria는 LLM이 판단한다. "단일 책임을 갖는다"는 것은 종료 코드로 측정할 수 없다. 이건 판단이 필요한 기준이고, 그래서 별도의 모델 인스턴스가 평가한다.

이 두 층의 분리가 중요하다. 기계가 판단할 수 있는 것은 기계에게 맡기고, 판단이 필요한 것은 판단하는 주체에게 맡긴다.

### JUDGE_FEEDBACK.md — 평가 이력의 영속성

매 거절마다 이 파일에 기록된다:

```
---
## 반복 7 — REJECTED (3 consecutive) — 2026-02-27 14:32:01

createUser 함수의 catch 블록이 에러를 삼키고 있습니다.
console.error로 출력하고 있지만 호출자에게 에러를 전파하지 않습니다.
에러는 명시적으로 처리하거나 re-throw해야 합니다.
```

에이전트는 Phase 0에서 이 파일을 읽는다. 이전 반복에서 뭐가 문제였는지, 같은 패턴이 반복되고 있는지 알 수 있다. 사람도 이 파일을 보면 루프가 어디서 막혔는지 한눈에 알 수 있다.

### progress.txt — 반복 간 작업 메모리

에이전트가 매 반복 끝에 스스로 기록하는 파일:

```
[반복 3] 완료: 사용자 생성 엔드포인트 + 입력 유효성 검사
         다음: 비밀번호 해싱 (bcrypt vs argon2id 결정 필요)
         배운 것: 기존 validator.ts에 이미 email 검증이 있었음 — 재사용함
```

에이전트의 컨텍스트는 반복마다 리셋된다. progress.txt는 이 리셋에도 살아남는 유일한 작업 기억이다. "내가 지난 반복에 뭘 했고, 다음에 뭘 해야 하는가"를 파일로 관리한다.

### .claude/autochecks.sh — 기본 모드의 자동 검증

Judge 모드 없이 기본 모드를 쓸 때도 완료 선언을 검증할 수 있다. 프로젝트에 이 파일이 있으면, 에이전트가 완료 신호를 내보낸 후 자동으로 실행된다. 실패하면 완료가 거절되고 실패 내용과 함께 재주입된다.

```bash
# .claude/autochecks.sh
#!/usr/bin/env bash
npm test
npx tsc --noEmit
npm run lint
```

Judge 모드 없이도 객관적 검증을 추가할 수 있는 경량 방법이다.

---

## 5. 세 가지 모드와 트레이드오프

gulf-loop는 세 가지 모드를 제공한다. 어떤 모드가 "더 좋은" 게 아니라, 상황에 따라 다른 트레이드오프를 선택하는 것이다.

### 기본 모드 (Basic)

**완료 조건**: 에이전트가 `<promise>COMPLETE</promise>` 출력 + `.claude/autochecks.sh` 통과 (있는 경우)

**적합한 경우**:
- 명확하고 검증 가능한 결과물이 있는 작업
- 자동화된 테스트가 충분해서 "테스트 통과 = 올바름"이 성립하는 경우
- 빠른 반복이 필요한 경우

**트레이드오프**:
- 평가자가 없다. 에이전트의 완료 선언을 신뢰한다.
- 코드 품질, 설계 결정 등 주관적 기준은 검증하지 않는다.

### Judge 모드

**완료 조건**: Auto-checks 통과 **AND** Claude Opus judge APPROVED

**적합한 경우**:
- 테스트 통과만으로는 "올바름"을 보장하기 어려운 작업
- 코드 품질, 아키텍처, 설계 원칙이 중요한 작업
- 사람이 매 반복 결과를 볼 수 없을 때 외부 기준으로 품질을 보장하고 싶은 경우

**트레이드오프**:
- 매 반복 Opus API 호출 비용이 든다.
- HITL 게이트가 있다. N번 연속 거절 시 사람이 개입해야 한다.
- 느리지만 정확도가 높다.

### 자율 모드 (Autonomous)

**완료 조건**: 기본 모드 또는 Judge 모드와 동일, 단 HITL 없음.

**적합한 경우**:
- 장시간 무인 실행이 필요한 경우
- 오류 누적 위험보다 처리량이 더 중요한 경우
- 에이전트가 막혀도 사람이 즉시 개입할 수 없는 환경

**트레이드오프**:
- HITL이 없다. 에이전트가 잘못된 방향으로 N번을 달려도 사람이 개입하지 않는다.
- 연속 거절 시 "전략 리셋"이 HITL을 대체하지만, 이 판단도 자동화된 것이다.
- 결과의 최종 검증은 merge 후 사람이 해야 한다.

**명심할 것**: 자율 모드는 "더 좋은" 모드가 아니다. 사람의 판단을 포기하는 대신 처리량을 얻는 트레이드오프다.

---

## 6. 자율 모드의 설계

### 왜 branch 기반인가

자율 모드에서 에이전트는 `gulf/auto-{timestamp}` 브랜치에서 작업한다. main에 직접 커밋하지 않는다.

이유: **main은 항상 검증된 상태여야 한다.**

에이전트가 자율적으로 작업하는 동안 main이 오염되면, 문제가 어디서 생겼는지 추적하기 어렵고, 다른 작업자의 작업에 영향을 준다. 브랜치 기반 작업은 에이전트의 작업을 격리하고, 승인된 것만 main에 통합한다.

롤백이 아니라 merge다. 문제가 생기면 되돌리는 게 아니라, 처음부터 merge가 성공 조건이다.

### Merge 흐름과 conflict 해소

```
_try_merge
  ├── flock 획득 (~/.claude/gulf-merge.lock)
  │     잠김 → 다음 반복에 재시도
  ├── git fetch + git rebase base_branch
  │     conflict → conflict 해소 태스크로 루프 재진입
  ├── .claude/autochecks.sh 실행
  │     실패 → 실패 상세와 함께 루프 재진입
  └── git merge --no-ff → 종료
```

#### Merge conflict의 의미

Merge conflict는 에러가 아니다. 두 개의 독립적인 변경이 같은 파일을 건드렸다는 신호다.

자율 모드에서 conflict가 발생하면 에이전트는 다음 지시와 함께 루프로 돌아온다:

1. 양쪽 변경의 의도를 파악한다 (`git log`와 `git show`로)
2. 두 의도를 모두 보존하는 병합 로직을 구현한다
3. 병합된 동작을 검증하는 테스트를 작성한다
4. 기존 테스트가 모두 통과하는지 확인한다
5. 완료 신호를 내보내면 merge가 재시도된다

이 접근의 핵심: **테스트가 병합의 정확성 증명이다.** 테스트가 통과한다는 것은 두 쪽의 로직이 모두 의도대로 동작한다는 기계적 증거다. "이쪽이 맞는 것 같다"는 판단이 아니라, 동작하는 코드로 증명한다.

#### 왜 직렬 merge인가

병렬 모드에서 여러 worker가 동시에 완료되면, merge는 flock으로 직렬화된다. 동시에 merge하지 않는다.

이유: **동시 merge는 conflict를 제어하기 어렵게 만든다.**

첫 번째 worker가 merge되면 main이 변경된다. 두 번째 worker는 업데이트된 main을 기준으로 rebase해야 한다. 이 순서를 보장하는 것이 flock이다. 처리량보다 통합의 정확성을 우선한다.

### 커밋 메시지의 "왜"

자율 모드에서 에이전트는 매 원자적 단위마다 커밋한다. 커밋 메시지는 **what이 아니라 why**를 담아야 한다:

```
feat(auth): use argon2id for password hashing

argon2id has stronger memory-hardness than bcrypt and is the current
OWASP recommendation. bcrypt is limited to 72 bytes and vulnerable to
password shucking. argon2id resistance scales with the memory parameter.

bcrypt was considered but ruled out due to the 72-byte limit —
passwords longer than that are silently truncated.
```

이유: 자율 모드에서 사람은 실시간으로 작업을 볼 수 없다. git history가 유일한 감사 추적이다. "무엇을 했는가"는 diff를 보면 알 수 있다. "왜 이 접근을 선택했는가, 왜 대안을 선택하지 않았는가"는 커밋 메시지가 없으면 사라진다.

5시간 후 루프가 끝났을 때, 커밋 히스토리를 읽으면 에이전트가 어떤 판단을 내리며 작업했는지 재구성할 수 있어야 한다.

### 연속 거절 시 전략 리셋

Judge 모드에서 N번 연속 거절이 발생하면:

- **HITL 모드**: 루프 일시정지 → 사람이 개입
- **자율 모드**: 전략 리셋 → 에이전트가 접근 방식을 근본적으로 바꿔 재시도

전략 리셋은 다음 메시지와 함께 루프를 재진입시킨다:

> "현재 접근이 N번 연속 거절됐습니다. 이것은 같은 방향으로 계속하면 안 된다는 신호입니다. JUDGE_FEEDBACK.md를 검토하고 거절 패턴의 근본 원인을 파악하세요. 구현 방식이나 아키텍처를 근본적으로 다르게 접근하세요."

이것이 HITL을 완전히 대체할 수는 없다. 하지만 자율 모드에서 취할 수 있는 최선이다.

---

## 7. 아직 없는 것 (실행 차 간극)

현재 gulf-loop의 실행 차 커버리지에는 구조적 간극이 있다. **루프 시작 전에 에이전트의 이해를 검증하는 단계가 없다.**

사람이 PROMPT를 작성한다. 루프가 시작된다. 에이전트가 PROMPT를 올바르게 해석했는지 확인 없이 반복이 진행된다. 20번을 돌고 나서야 "아, 내가 원한 게 이게 아니었는데"를 발견할 수 있다.

### 예정: `/gulf-loop:align`

루프 시작 전 정렬 단계. 에이전트가 PROMPT를 읽고 자신의 이해를 사람에게 제시해 확인받는다.

```bash
/gulf-loop:align "$(cat PROMPT.md)"
# 에이전트:
# "목표를 다음과 같이 이해했습니다: [재진술]
#  실행 계획: [단계별 분해]
#  가정하는 것들: [목록]
#  확인되면 루프를 시작하겠습니다. 수정이 필요하면 알려주세요."
```

비용 문제가 되기 전에 실행 차를 닫는다. 20번 반복 후 방향 수정보다, 0번째에서 방향을 확인하는 게 훨씬 싸다.

### 예정: `milestone_every` — 선제적 체크포인트

현재 HITL 게이트는 **반응적**이다. 평가가 N번 실패한 후에만 트리거된다.

선제적 체크포인트는 judge 결과와 무관하게 일정 간격으로 루프를 일시정지한다.

```yaml
milestone_every: 5  # 5번마다 사람 검토
```

"잘 가고 있는지"를 주기적으로 확인하는 것이다. 실패 감지가 아니라 진행 상황 확인.

### 예정: `EXECUTION_LOG.md`

에이전트가 매 반복 자신의 실행 이해를 기록하는 컨벤션:

```markdown
## 반복 4
완료: 사용자 생성 엔드포인트, 입력 유효성 검사
남은 것: 비밀번호 해싱 (미시작), 엣지 케이스 테스트
발견한 간극: bcrypt와 argon2id 중 어느 것을 사용할지 불분명 — 명세 필요
```

사람이 HITL 일시정지 순간이 아닌, 언제든 루프 상태를 들여다볼 수 있게 된다.

---

## 8. 설치

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

## 9. 사용법

### 기본 모드

완료 조건 = 에이전트가 `<promise>COMPLETE</promise>` 출력.

```bash
/gulf-loop:start "$(cat PROMPT.md)" --max-iterations 30
```

`.claude/autochecks.sh`가 있으면 완료 신호 감지 후 자동 실행. 실패 시 완료 거절.

```bash
# .claude/autochecks.sh
#!/usr/bin/env bash
npm test
npx tsc --noEmit
npm run lint
```

### Judge 모드

완료 조건 = auto-checks 통과 **AND** Opus judge 승인.

`RUBRIC.md` 먼저 작성 (`RUBRIC.example.md` 참고):

```bash
/gulf-loop:start-with-judge "$(cat PROMPT.md)" \
  --max-iterations 30 \
  --hitl-threshold 5
```

### 자율 모드

루프가 사람을 기다리며 멈추지 않는다. 완료 시 자동으로 branch merge.

```bash
# 기본 자율 모드
/gulf-loop:start-autonomous "$(cat PROMPT.md)" \
  --max-iterations 200 \
  --base-branch main

# 자율 + judge (HITL 없이 judge 평가)
/gulf-loop:start-autonomous "$(cat PROMPT.md)" \
  --max-iterations 200 \
  --with-judge \
  --hitl-threshold 10
```

### 병렬 모드

N개의 worktree를 만들고 각각 독립적인 자율 루프를 실행. merge는 자동 직렬화.

```bash
/gulf-loop:start-parallel "$(cat PROMPT.md)" \
  --workers 3 \
  --max-iterations 200 \
  --base-branch main
```

출력된 각 worktree를 별도 Claude Code 세션에서 열고 `/gulf-loop:resume` 실행.

### 명령어 전체 목록

| 명령어 | 설명 |
|--------|------|
| `/gulf-loop:start PROMPT [--max-iterations N] [--completion-promise TEXT]` | 기본 루프 |
| `/gulf-loop:start-with-judge PROMPT [--max-iterations N] [--hitl-threshold N]` | Judge 포함 루프 |
| `/gulf-loop:start-autonomous PROMPT [--max-iterations N] [--base-branch BRANCH] [--with-judge]` | 자율 루프 (HITL 없음) |
| `/gulf-loop:start-parallel PROMPT --workers N [--max-iterations N] [--base-branch BRANCH]` | 병렬 worktree 루프 |
| `/gulf-loop:status` | 현재 반복 횟수 확인 |
| `/gulf-loop:cancel` | 루프 중단 |
| `/gulf-loop:resume` | HITL 일시정지 후 재개 / 사전 초기화된 worktree 시작 |

---

## 10. 기존 구현과의 비교

### vs `anthropics/ralph-wiggum`

동일한 Stop hook 아키텍처. ralph-wiggum의 핵심은 96줄짜리 stop hook — 완료 신호를 확인하고 같은 프롬프트를 재주입한다. gulf-loop가 추가한 것:

| | ralph-wiggum | gulf-loop |
|---|---|---|
| 설계 프레이밍 | 루프 메커니즘 | HCI gulf 인식 루프 |
| 완료 판정 주체 | 작업 에이전트 본인 | 별도 Opus judge (judge 모드) |
| 실행 차 대응 | 없음 | Phase 프레임워크 + 언어 트리거 매 반복 주입 |
| 평가 차 대응 | 완료 약속만 | RUBRIC.md + judge + JUDGE_FEEDBACK.md |
| HITL | 없음 | 핵심 설계 — 평가 수렴 실패 시 인간에게 제어권 |
| 자율 모드 | 없음 | 브랜치 기반, 자동 merge, 전략 리셋 |
| 병렬 처리 | 없음 | worktree + 직렬 merge |
| 완료 감지 | JSONL 트랜스크립트 파싱 | `last_assistant_message` 필드 직접 사용 |

### vs `snarktank/ralph` (외부 bash 루프)

근본적으로 다른 아키텍처. 외부 루프는 각 반복마다 완전히 새로운 Claude 세션을 시작한다.

| | snarktank/ralph | gulf-loop |
|---|---|---|
| 아키텍처 | 외부 bash → claude 호출 | Stop hook 내부 루프 |
| 반복당 컨텍스트 | 완전 초기화 | 누적 |
| 적합한 반복 수 | 100번 이상 | 50번 이하 |
| 메모리 | 파일만 | 파일 + 누적된 대화 맥락 |
| Gulf 인식 | 설계 목표 아님 | 핵심 설계 목표 |

컨텍스트가 누적되면 장기적으로 "dumb zone" — 컨텍스트가 40–60% 이상 찰수록 모델 성능이 저하되는 구간 — 에 빠질 위험이 있다. 장기 실행에서는 외부 루프 방식이 유리하다. 단기 작업에서는 누적 컨텍스트가 이전 반복의 맥락을 활용할 수 있어 유리하다.

---

## 11. 참고문헌

- Norman, D. A. (1988). *The Design of Everyday Things*. — 실행 차와 평가 차 개념의 원전
- [ghuntley.com/ralph](https://ghuntley.com/ralph) — Geoffrey Huntley, Ralph Loop 기법 창시자
- [anthropics/claude-code plugins/ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) — 공식 Stop hook 플러그인 (96줄)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks) — Stop hook 레퍼런스
