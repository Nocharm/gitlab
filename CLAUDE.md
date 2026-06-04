# gitlab-docker-ci-deploy

사내 서버에 Docker로 GitLab CE+Runner를 띄우고, push된 프로젝트를 `.gitlab-ci.yml`에 따라
같은 서버의 **자동 할당 포트**에 배포하는 Infra-as-Code. **bash/shell + Docker 중심**(Python
코드는 아직 없음 — reconciler가 다음 phase). 실 배포는 `docs/RUNBOOK.md`.

## Commands
```bash
PATH=/opt/homebrew/bin:$PATH bats tests/        # 단위 테스트 (mac은 homebrew bash5 필수)
shellcheck scripts/* scripts/lib/*              # 셸 린트
docker compose --env-file .env.example -f compose/gitlab.compose.yml config   # compose 검증
# 로컬에서 deploy-app 단독 테스트: docs/LOCAL-TEST.md
```

## Architecture
- `compose/` GitLab CE + Runner(shell executor, docker.sock+GID 마운트) / `runner/` 러너 이미지(+deploy-app baked-in)
- `scripts/lib/registry.sh` 포트 영속매핑(jq) · `scripts/deploy-app` 배포 헬퍼(deploy/reset/destroy/purge)
- 상태: `/srv/deploy/registry.json`(호스트, key=`CI_PROJECT_PATH`) · 실 배포값은 `.env`(gitignore, 커밋금지)
- 문서: `docs/RUNBOOK.md`(서버) · `docs/LOCAL-TEST.md`(로컬) · `docs/APP-DEPLOY-GUIDE.md`(앱 팀)

## Gotchas (실전)
- **bats on mac**: homebrew bash5로 실행. 3.2는 한글 `@test`명에서 0개 실행됨
- **CRLF**: Windows 경유 전송 시 `bash\r` 에러. `.gitattributes`(LF강제)+Dockerfile이 이미지 내 LF화. `.env`는 직접 `tr -d '\r'`
- **shell-executor job = `gitlab-runner` 유저(비-root)**: docker 소켓 위해 그 유저를 호스트 docker GID 그룹에 추가(Dockerfile ARG)
- **포트 할당**: 러너 컨테이너는 호스트 netns를 못 봄 → deploy-app이 실제 `-p` 바인드 성공까지 재시도. 등록은 바인드 성공 후에만
- **GitLab 19**: 러너 토큰 페이지 UI 버그 → `docker exec gitlab gitlab-rails runner 'puts Ci::Runner.last.token'`. 토큰 등록은 url/token/executor만(나머지 reserved)
- **`sudo cmd > file`** 은 리다이렉트가 비권한 → `... | sudo tee file`

---

## Working Style — 최우선 (모든 룰보다 먼저)

**모든 작업의 행동 기반.** 아래 도메인 룰과 충돌해도 이 가이드의 원칙이 우선한다.

@rules/guidelines.md

---

## Rules — 범용 (유지)

@rules/common/comments.md
@rules/common/naming.md
@rules/common/git.md
@rules/common/security.md
@rules/common/error-handling.md
@rules/common/dependencies.md
@rules/common/documentation.md
@rules/common/testing.md

## Rules — 백엔드/Docker (아니면 이 블록 삭제)

배포/컨테이너 전제 규칙. 라이브러리·CLI·프론트 단독 프로젝트면 이 블록을 통째로 삭제한다.

@rules/backend/config.md
@rules/backend/docker.md
@rules/backend/sync-checklist.md

## Language-Specific Rules

프로젝트에서 사용하는 언어만 남기고 나머지 줄은 삭제한다.

@rules/languages/python.md
