# Git Conventions

```
type(scope): English summary — 한국어 요약

# Types: feat, fix, docs, refactor, test, chore, perf
# Scope: optional, module or feature name
```

- Commit messages explain **WHY**, not WHAT.
- **Write the description in both English and Korean** so it's easy to grasp at a glance (`type(scope): English summary — 한국어 요약`).
- One logical change per commit.
- Never amend published commits without explicit request.
- Never force-push to main/master.
- Prefer specific `git add <files>` over `git add .` or `git add -A`.

## Before Every Commit

커밋 직전 항상 `PROGRESS.md` (저장소 루트의 진행 현황 로그 — 없으면 생성) 를 갱신한다: 무엇을·왜 바꿨는지 기록한 뒤 스테이징·커밋한다.
