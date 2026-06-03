# Progress

프로젝트 진행 현황 로그. 커밋 직전 갱신한다 (`rules/common/git.md` 규칙).

## 2026-06-03 (Task 2–8)

- Task 2 `scripts/deploy-app`: deploy/reset/destroy/purge + 동적 포트 할당(key=CI_PROJECT_PATH).
  bats 4/4 pass(docker 스텁), shellcheck clean. 검증을 호스트 docker 기준(`docker inspect`)으로,
  볼륨 teardown은 mac 호환(`xargs -r` 미사용)으로 구현.
- Task 4·5 compose: `compose/gitlab.compose.yml`(CE+영속 볼륨), `compose/runner.compose.yml`
  (docker.sock+GID+registry 볼륨). 둘 다 `docker compose config` valid. `.env.example` 추가.
- Task 6 `scripts/clean_slate.sh`·`register_runner.sh`: shellcheck clean.
- Task 7 `examples/sample-app/`: nginx 데모 + 4-job `.gitlab-ci.yml`. 빌드 ok.
- Task 8 README 셋업 섹션 + `docs/RUNBOOK.md`(무한 pending 체크리스트 + 71서버 스모크).
- Task 3 `runner/Dockerfile`: gitlab-runner+docker CLI+jq+deploy-app baked-in (빌드 검증 별도).
- 실행 방식: 세션 한도로 Task 3~8은 subagent 대신 controller 직접 구현(정적 파일+결정적 검증).

## 2026-06-03 (Task 1)

- `scripts/lib/registry.sh` 구현: 포트 레지스트리 CRUD + `find_free_port` + `parse_volumes`.
  왜: deploy-app이 소싱할 순수 Bash 라이브러리 — jq 기반 JSON 영속 매핑.
- `tests/registry.bats` TDD: 9개 테스트 전부 pass, shellcheck 경고 없음.
  (macOS Bash 3.2에서 bats 1.13 Korean 테스트명 인코딩 문제 발생 → `/opt/homebrew/bin/bash`
  설치로 해결; `PATH=/opt/homebrew/bin:$PATH bats` 로 실행해야 함.)

## 2026-06-03

- 템플릿(claude-code-template)에서 프로젝트 부트스트랩. Python+Docker 스택에 맞춰
  `CLAUDE.md` import 정리(typescript 룰 제거), 템플릿 메타 문서(`docs/template/`) 제거.
  왜: 이 저장소를 71서버 GitLab Docker 배포 IaC로 전환.
- 루트 `README.md` placeholder → 프로젝트 개요로 교체. 왜: `documentation.md` 규칙상
  의미있는 커밋 전 README를 실제 내용으로 채워야 함.
- 설계 스펙 작성: `docs/superpowers/specs/2026-06-03-gitlab-docker-ci-deploy-design.md`.
  shell executor + 동적 포트 할당 + 데이터 라이프사이클(reset/destroy/purge) 합의.
  reconciler(repo 실삭제 자동 정리)는 다음 phase로 분리.
- 구현 계획 작성: `docs/superpowers/plans/2026-06-03-gitlab-docker-ci-deploy.md`.
  Task 0~8(레지스트리 로직 TDD → deploy-app → 러너 이미지 → compose → 스크립트 →
  데모앱 → 검증 런북). 로컬 검증(bats/shellcheck/compose config)과 71서버 수동 검증 분리.
