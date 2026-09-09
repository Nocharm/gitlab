# Progress

프로젝트 진행 현황 로그. 커밋 직전 갱신한다 (`rules/common/git.md` 규칙).

## 2026-09-09 (Puma 워커 8개 고정)

- 현장: 서버 메모리 사용량이 위험 수준. Puma 워커가 자동 산정(호스트 코어 수 기반)이라
  코어가 많은 71서버에서 워커가 과다 생성되고, 워커당 RSS ~1GB+ 로 메모리를 잠식.
- `gitlab.compose.yml`: `puma['worker_processes'] = 8` 로 고정(자동 산정 off. 12로 잡았다가
  메모리 여유를 더 두려고 8로 내림).
  새 `.env` 값 없이 하드코딩 — 이 repo는 단일 서버 전용이고 배포마다 바뀌는 값이 아님.
  반영은 pull → `up -d`(데이터 볼륨 보존).
- `README.md`: "리소스 튜닝 (Puma 워커)" 절 추가 — 고정 이유와 반영·확인 명령.

## 2026-06-07 (Keycloak OIDC: redirect_uri 명시)

- 현장: SSL 해결 후 Keycloak에서 `Invalid parameter: redirect_uri`. 주소창 auth 요청에
  `redirect_uri` 파라미터가 아예 없음 = GitLab이 미전송(`discovery:false`에선 omniauth가
  external_url 기반 자동생성을 안 함). Keycloak 등록 문제 아님.
- `gitlab.compose.yml`: `client_options.redirect_uri`를
  `http://${GITLAB_HOSTNAME}:${GITLAB_HTTP_PORT}/users/auth/openid_connect/callback`로 명시.
  새 `.env` 값 불필요 — pull→`up -d --force-recreate`.

## 2026-06-07 (Keycloak OIDC: discovery off — http transport 강제)

- 현장: issuer/로드값/광고 엔드포인트 모두 http인데도 버튼 클릭 시 GitLab이 `https://IP:8080`로
  붙어 `SSL record layer failure` 지속(=request phase의 discovery 호출이 https로 감).
- `gitlab.compose.yml`: `discovery: false` + `authorization/token/userinfo/jwks/end_session_endpoint`를
  `${KEYCLOAK_ISSUER}` 기준으로 명시 → 전송 스킴이 issuer(http)와 동일하게 고정. discovery 단계 제거로
  https 강제 경로 자체를 우회. `client_auth_method: 'query'→'basic'`(Keycloak 기본 client_secret_basic).
  새 `.env` 값 불필요 — pull→`up -d --force-recreate`만.

## 2026-06-07 (Keycloak issuer 탐지 헬퍼)

- `docs/keycloak/probe-issuer.sh`: OIDC 로그인 SSL/경로 에러 디버그용. GitLab 컨테이너에서
  Keycloak(`182.199.63.71:8080`, http, realm=`gitlab`) realm존재·SSL리다이렉트·issuer를 신/구(`/auth`)
  경로로 찔러 올바른 `KEYCLOAK_ISSUER`를 출력. 왜: 서버에서 긴 명령 옮겨치기 어려워 pull→실행용.
  현장 결과 realm `gitlab` 404 → 원인은 realm명 혼동: **realm=`ai-portal`, `gitlab`은 client id**.
  스크립트 `REALM=ai-portal`로 교정. 클릭 시 동일 SSL 에러 지속 → `[F]` 적용상태 점검 추가
  (.env값 / GitLab이 로드한 issuer / discovery 엔드포인트 스킴): up -d 미반영 vs Keycloak이
  https 엔드포인트 광고를 구분. KEYCLOAK_ISSUER는 discovery의 `issuer` 문자열과 글자 그대로 일치해야 함.

## 2026-06-07 (서버 반영 절차 + 로그인 쇼케이스 이미지 후보)

- `docs/RUNBOOK.md`: 이미 떠 있는 서버에 변경 반영하는 "git pull → `docker compose up -d`"
  절차 추가(데이터 볼륨 보존, `--remove-orphans` 금지 명시).
- `docs/keycloak/showcase/`: Keycloak 로그인 화면용 "connected service" 쇼케이스 썸네일
  후보 4종(`cand-1..4.png`, 1280x800) + 2x2 대조 시트(`contact.png`) + 생성기 `gen_mocks.py`.
  GitLab 스켈레톤(좌측 사이드바+tanuki 마크+Projects 리스트 ghost), accent/gradient/mood만 변주.
  → Candidate 2(soft) 채택. `gitlab-login-showcase.png`만 남기고 나머지 png/html/생성기 정리.

## 2026-06-07 (Keycloak OIDC SSO 연동)

- `gitlab.compose.yml`: GITLAB_OMNIBUS_CONFIG에 omniauth `openid_connect` provider 추가.
  왜: 기존 유저·데이터(named 볼륨)를 건드리지 않고 로그인 수단만 추가. 패스워드 로그인은
  끄지 않아 병행 유지(설정 오류 시 락아웃 방지). `auto_link_user`로 기존 유저 이메일 매칭 연결,
  `block_auto_created_users=true`로 신규 외부 유저는 승인 게이트.
- 시크릿/환경값은 `.env`로 분리(`KEYCLOAK_ISSUER/CLIENT_ID/CLIENT_SECRET`), `.env.example`은
  placeholder. **함정:** 빈 값 줄의 인라인 주석을 compose `--env-file`이 값으로 흡수 →
  `secret: '# ...'`로 들어가던 버그를 `config` 검증으로 잡고 주석을 윗줄로 이동.
- `docs/RUNBOOK.md`에 "선택: Keycloak SSO 연동" 절차(Keycloak client→.env→up -d→유저 동작) 추가.
- 검증: `docker compose --env-file .env.example -f compose/gitlab.compose.yml config` valid,
  빈 secret이 `secret: ''`로 정상 보간(부팅 영향 없음).

## 2026-06-04 (포트 충돌 처리 + 앱 배포 가이드)

- deploy-app: 비-docker 프로세스가 점유한 호스트 포트로 충돌(`port is already allocated`).
  러너 컨테이너는 호스트 netns를 못 봐 사전 탐지 불가 → **실제 `docker run -p` 바인드 성공까지
  다음 포트로 자동 재시도**하도록 단일 배포 로직 수정. bats 5/5(재시도 케이스 포함).
- 앱 팀용 자동배포 가이드 `docs/APP-DEPLOY-GUIDE.md` + 템플릿 `examples/gitlab-ci.template.yml`
  ($CI_PROJECT_PATH_SLUG 사용, deploy/reset/destroy/purge). README에서 링크.

## 2026-06-04 (서버 배포 중 수정)

- Dockerfile: COPY 후 `sed 's/\r$//'`로 이미지 안 deploy-app/registry.sh를 무조건 LF화
  (소스가 CRLF여도 shebang `bash\r` 에러 안 나게). RUNBOOK에 `/srv/deploy` 필수 준비 단계 +
  트러블슈팅 표(CRLF/권한/소켓/register/UI버그/orphan) 추가.

- 배포 job의 docker 소켓 permission denied: 이미지가 `gitlab-runner run --user gitlab-runner`라
  **잡은 gitlab-runner(비-root) 유저로 실행** → group_add 989는 데몬에만 붙고 잡 유저엔 없음.
  → Dockerfile에서 `gitlab-runner` 유저를 호스트 docker GID 그룹에 추가(ARG DOCKER_GID),
  runner.compose build args로 전달. /srv/deploy 는 호스트에서 쓰기권한 부여 필요(chmod).

- `register_runner.sh`: GitLab 19 authentication-token 등록은 `--locked/--tag-list/--run-untagged`이
  reserved → FATAL. 해당 옵션 제거(url/token/executor만). 태그 등은 UI 러너 생성 시 설정.
- `.gitattributes` 추가(LF 강제) — Windows 경유 전송 시 CRLF로 스크립트 깨지는 문제 방지.

## 2026-06-04 (71서버 설정 반영)

- 실 배포 대상 사내 71서버 확정. 실제 호스트·포트·GID는 커밋하지 않고 서버 `.env`에만 둠
  (security.md/config.md) — `.env.example`은 placeholder, 런북은 `.env` 참조로 동작.
- `gitlab.compose.yml`: `nginx['listen_port']=80` + listen_https off로 external_url 포트와 분리
  (프록시 뒤 인식 일관화) — 러너 생성 UI 에러 가설 대응이자 표준 설정. git-ssh 미사용(http clone).

## 2026-06-03 (디버깅: 러너 생성 UI 에러)

- 증상: GitLab UI에서 러너 생성 클릭 시 상세(토큰) 페이지로 못 넘어가고 에러.
- 원인: GitLab 19.0.1에서 `runnerCreate` mutation은 성공(러너 DB 생성됨)하나 생성 직후
  register 페이지(프론트엔드 webpack 에셋/렌더)가 깨짐. 서버 예외는 없음 = GitLab 자체 UI 이슈.
- 해결: UI 우회 — `gitlab-rails runner 'puts Ci::Runner.last.token'`로 토큰 직접 추출.
  `docs/LOCAL-TEST.md` 4단계를 콘솔 토큰 추출 방식으로 보강.

## 2026-06-03 (로컬 UI 테스트 지원)

- `master`→`main` 리네임 + 구현 브랜치 머지(FF).
- 서버 접근 불가 → 로컬 Docker Desktop에서 GitLab UI 푸시 배포를 재현하기 위해
  `compose/runner.local.yml`(host-gateway 매핑 + registry named 볼륨) + `docs/LOCAL-TEST.md` 추가.
  왜: mac은 컨테이너 localhost 격리·`/srv` 바인드 불가라 서버용 compose만으론 로컬 재현 불가.

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
