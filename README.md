# gitlab-docker-ci-deploy

사내 71서버에 **Docker로 GitLab CE + Runner를 기동**하고, 각 프로젝트가 푸시한
`.gitlab-ci.yml`에 따라 **같은 서버의 자동 할당 포트로 앱을 배포·교체·삭제**하는
Infra-as-Code 저장소.

## 누가 쓰나

71서버 운영/배포 담당자. GitLab·Runner를 재현 가능하게 띄우고, 사내 프로젝트들이
공통 배포 헬퍼(`deploy-app`)로 셀프 배포하도록 만든다.

## 동작 개요

- GitLab CE + Runner를 compose로 71서버에 기동 (Runner: `shell` executor, 호스트
  `docker.sock` 마운트 → 호스트 docker 데몬에 앱 배포).
- 첫 배포 시 포트 범위에서 **빈 포트 자동 할당**, 이후 같은 프로젝트는 같은 포트 재사용
  (영속 매핑 `registry.json`).
- 재배포 = 컨테이너 교체(**데이터 보존**). `--reset`(데이터 초기화) / `--destroy`(서비스만
  내림) / `--purge`(데이터 포함 완전 삭제) 지원.
- 가드레일: 프로젝트 전용 러너 + 태그 매칭 + protected branch 한정.

> ⚠️ docker 소켓 마운트 = 호스트 root 권한. 이 러너에 파이프라인을 돌릴 수 있는 사람은
> 사실상 71서버 root 권한을 가진다. 위 가드레일로 완화한다.

## 배포 (빠른 시작)

실제 호스트·포트·GID는 **`.env`에만** 둔다(커밋 금지 — `.env.example`은 placeholder).
단계별 전체 절차·검증·트러블슈팅은 **[`docs/RUNBOOK.md`](docs/RUNBOOK.md)** 가 정본.

```bash
cp .env.example .env                 # 실제 값으로 채움 (DOCKER_GID는 `getent group docker`)
set -a; source .env; set +a
docker compose --env-file .env -f compose/gitlab.compose.yml up -d            # GitLab (3~5분)
# UI(Admin→CI/CD→Runners→New instance runner)에서 러너 생성 → 토큰을 .env RUNNER_TOKEN 에
docker compose --env-file .env -f compose/runner.compose.yml up -d --build    # Runner
bash scripts/register_runner.sh                                               # 등록 → online
```

앱 repo에는 `examples/sample-app/.gitlab-ci.yml`을 참고한 `.gitlab-ci.yml`을 둔다.
설계: [`docs/superpowers/specs/2026-06-03-gitlab-docker-ci-deploy-design.md`](docs/superpowers/specs/2026-06-03-gitlab-docker-ci-deploy-design.md) ·
서버 없이 로컬(mac) 시험: [`docs/LOCAL-TEST.md`](docs/LOCAL-TEST.md).

## 계획된 구조

```
compose/    GitLab·Runner compose 파일
runner/     Runner 이미지(Dockerfile) + deploy-app 헬퍼
scripts/    clean_slate / register_runner / deploy-app
examples/   sample-app + .gitlab-ci.yml (전체 체인 스모크)
```

## 다음 단계 (별도 phase)

repo 실삭제를 GitLab API로 감지해 `deploy-app --purge`를 자동 호출하는 reconciler(Python).
