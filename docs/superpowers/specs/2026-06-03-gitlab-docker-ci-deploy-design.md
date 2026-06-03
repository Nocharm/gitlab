# GitLab Docker CI 자동 배포/삭제 — 설계 스펙

- 날짜: 2026-06-03
- 상태: 승인됨 (브레인스토밍 합의 완료)
- 대상 서버: 사내 "71서버" (호스트, 작업자 sudo 보유, 기존 컨테이너 다수 상주)

## 1. 목적 (Goal)

사내 71서버에 **Docker로 GitLab CE + GitLab Runner를 기동**하고, 각 프로젝트가 푸시한
`.gitlab-ci.yml`에 따라 **같은 71서버의 포트로 앱을 자동 배포**한다. 재배포 시 기존
컨테이너를 교체하고, 수동 트리거로 정리(삭제)할 수 있다.

실무에서 겪은 **job 무한 pending**(러너 등록은 됐으나 배포 권한/`config.toml` 문제)을
처음부터 재현 가능한 형태로 잡는 것이 핵심 동기다.

## 2. 비목표 (Non-Goals / 이번 범위 제외)

- **reconciler (repo 실삭제 자동 감지)** — 다음 phase. 이번엔 *수동 destroy job*까지만.
  따라서 "repo를 GitLab에서 삭제하면 컨테이너도 자동 정리"는 이번 범위에서 **미충족**이며,
  사용자가 삭제 전 destroy job을 수동 실행해야 한다.
- 브랜치/MR별 ephemeral review app (동적 환경) — 채택 안 함.
- GitLab 자체의 HA/백업/SSO 등 운영 고도화.

## 3. 핵심 결정 (Decisions)

| # | 항목 | 결정 |
|---|------|------|
| D1 | GitLab/Runner 기동 | 둘 다 Docker(compose)로 71서버에 기동 |
| D2 | Runner executor | **shell** (러너는 컨테이너, 호스트 `docker.sock` + docker 그룹 GID 마운트) |
| D3 | 배포 메커니즘 | 러너 안 `docker` CLI → 마운트된 소켓으로 **호스트 docker 데몬** 제어 → 앱이 71서버 본체에 뜸 |
| D4 | 포트 모델 | **동적 자동 할당 + 영속 매핑**. 첫 배포 시 범위에서 빈 포트 할당, 이후 같은 key는 같은 포트 재사용 |
| D5 | 레지스트리 key | **`CI_PROJECT_PATH`** (namespace/이름). 이름/경로 변경 시 새 key → 새 포트 |
| D6 | 재배포 | 같은 key → 기존 컨테이너 `rm -f` 후 새로 `run`. **named 볼륨은 보존**(데이터 유지) |
| D7 | 라이프사이클 | **기본 데이터 보존.** `--reset`=볼륨만 초기화 후 재배포 / `--destroy`=서비스만 내림(볼륨 보존) / `--purge`=컨테이너+볼륨+포트 전부 제거 |
| D11 | repo 삭제 시 데이터 | repo 실삭제 → `--purge`(데이터 포함 완전 제거). 이번 phase는 수동 `--purge` job, **자동화는 다음 phase reconciler가 `--purge` 호출** |
| D8 | 배포 헬퍼 | `deploy-app`을 **러너 이미지에 baked-in** — 앱은 ci에서 호출만 |
| D9 | 가드레일 | 프로젝트/그룹 전용 러너 + 태그 매칭 강제 + protected branch 한정 |
| D10 | clean-slate | 0단계로 기존 GitLab/러너 잔재 인벤토리 & 정리 |

## 4. 아키텍처

```
71 서버 (호스트)
├─ [컨테이너] GitLab CE              웹/SSH 포트, 영속 볼륨(config/logs/data)
├─ [컨테이너] GitLab Runner          executor=shell, /var/run/docker.sock + GID 마운트
│     │  CI job(shell) 내부에서 docker CLI 실행
│     ▼  (소켓 → 호스트 docker 데몬)
├─ [컨테이너] app-A  :9000           ← 호스트 본체에 배포, 포트 호스트 바인딩
├─ [컨테이너] app-B  :9001
└─ /srv/deploy/registry.json         포트 영속 매핑 (러너에 마운트)
```

**보안 리스크 (명문화 필수):** docker 소켓 = 호스트 root. 이 러너에 파이프라인을 돌릴 수
있는 사람은 사실상 71서버 root 권한을 갖는다. → D9 가드레일로 완화.

## 5. 저장소 레이아웃 (이 repo = Infra-as-Code)

```
gitlab/
├─ compose/
│  ├─ gitlab.compose.yml       GitLab CE 서비스
│  └─ runner.compose.yml       Runner 서비스 (소켓 + GID + registry 볼륨)
├─ runner/
│  └─ Dockerfile               gitlab/gitlab-runner + docker CLI + compose plugin + deploy-app
├─ scripts/
│  ├─ clean_slate.sh           기존 gitlab/runner 컨테이너·볼륨·네트워크 인벤토리 & 정리
│  ├─ register_runner.sh       러너 등록 (token, executor=shell, tags, locked, run_untagged=false)
│  └─ deploy-app               공유 배포 헬퍼 (러너 이미지에 COPY)
├─ examples/sample-app/        데모 앱 + .gitlab-ci.yml (전체 체인 스모크 검증)
├─ .env.example                포트 범위, 등록 토큰, 태그, docker GID, GitLab 호스트/포트
├─ README.md                   프로젝트 설명 (placeholder 교체 — 구현 1번 작업)
└─ PROGRESS.md
```

## 6. 컴포넌트 상세

### 6.1 `deploy-app` (러너 이미지 baked-in)

진입점:
```
deploy-app <name>             # 단일 이미지: repo 루트 Dockerfile 빌드 후 배포 (볼륨 보존)
deploy-app <name> --compose   # compose 스택 앱
deploy-app <name> --reset     # 볼륨 비우고 새로 배포 (서비스 유지, 데이터만 초기화)
deploy-app <name> --destroy   # 서비스만 내림 (컨테이너 제거, 볼륨 보존)
deploy-app <name> --purge     # 완전 제거 (컨테이너 + 볼륨 + 레지스트리 entry → 데이터 포함)
```

동적 포트 할당 + 교체 로직:
```
key = $CI_PROJECT_PATH
flock /srv/deploy/registry.json:            # 동시 배포 레이스 방지
  if key in registry:
    port = registry[key].port               # 재사용
  else:
    port = PORT_MIN..PORT_MAX 중 (레지스트리 미사용 AND 실제 LISTEN 안 함) 첫 포트
    registry[key] = {port, container:<name>}
docker build -t <name>:$CI_COMMIT_SHORT_SHA .
docker rm -f <name> 2>/dev/null || true     # D6: 컨테이너만 교체 (볼륨은 그대로 둠)
docker run -d --name <name> -p ${port}:${APP_PORT} \
  $(named 볼륨 마운트: DEPLOY_VOLUMES 파싱) --restart unless-stopped <name>:$SHA
검증: 해당 port LISTEN 확인 + 컨테이너 running → 실패 시 job 실패(비0 종료)
```

호스트 바인딩 포트(`${port}`)는 동적 할당값, 컨테이너 내부 포트(`${APP_PORT}`)는 앱마다
달라 ci 변수로 전달받는다(기본 80).

**볼륨(데이터 보존):** 앱이 `DEPLOY_VOLUMES` ci 변수로 영속 경로 선언(`vol:/path` 콤마 구분).
`deploy-app`이 named 볼륨 `<name>_<vol>`로 마운트 → 재배포해도 데이터 유지.

포트 충돌 처리: 대상 포트를 우리 관리 밖 컨테이너가 점유 → 같은 `<name>`이면 교체, 아니면
**실패시키고 보고** (안전 우선).

라이프사이클 동작 (단일/compose 동일 규칙):
- `--reset`: named 볼륨 제거 → 재배포 (서비스 유지, 데이터 초기화). 데이터 손실이라 수동 job.
- `--destroy`: 컨테이너 제거 + 레지스트리 entry 삭제(포트 반납). **볼륨 보존**(나중 복구 가능).
- `--purge`: 컨테이너 + named 볼륨 + 레지스트리 entry 전부 제거(compose는 `down -v`). 데이터 포함 완전 삭제.

### 6.2 `register_runner.sh`

```
gitlab-runner register --non-interactive \
  --url "$CI_SERVER_URL" --token "$RUNNER_TOKEN" \
  --executor shell \
  --tag-list "$RUNNER_TAGS" \      # 예: shell-71
  --run-untagged=false \           # 태그 없는 job 차단
  --locked=true                    # 프로젝트 전용
```
생성된 `config.toml`은 토큰 포함 → **gitignore**, 절대 커밋 금지.

### 6.3 앱 `.gitlab-ci.yml` (examples/sample-app)

```yaml
variables:
  APP_PORT: "80"                       # 컨테이너 내부 포트
  DEPLOY_VOLUMES: "data:/var/lib/app"  # 영속 데이터 경로(없으면 무상태)
deploy:
  stage: deploy
  tags: [shell-71]                 # 러너 태그와 일치 (불일치 = 무한 pending)
  rules:
    - if: $CI_COMMIT_REF_PROTECTED == "true"
  script:
    - deploy-app sample-app         # 재배포: 데이터 보존
reset:                             # 데이터 초기화 (서비스 유지)
  stage: deploy
  tags: [shell-71]
  when: manual
  script:
    - deploy-app sample-app --reset
destroy:                           # 서비스만 내림 (데이터 보존)
  stage: deploy
  tags: [shell-71]
  when: manual
  script:
    - deploy-app sample-app --destroy
purge:                             # 완전 삭제 (데이터 포함)
  stage: deploy
  tags: [shell-71]
  when: manual
  script:
    - deploy-app sample-app --purge
```

### 6.4 `clean_slate.sh`

기존 `gitlab` / `gitlab-runner` 컨테이너·볼륨·네트워크를 인벤토리로 출력 → 사용자 확인 후
정리. (두 번 띄운 잔재/옛 러너 등록이 무한 pending 원인일 수 있음.)

## 7. 설정 (.env)

| 변수 | 용도 | 예 |
|------|------|----|
| `GITLAB_HOSTNAME` | GitLab external_url 호스트 | gitlab.71.internal |
| `GITLAB_HTTP_PORT` / `GITLAB_SSH_PORT` | GitLab 웹/SSH 포트 | 8929 / 2289 |
| `RUNNER_TOKEN` | 러너 등록 토큰 (프로젝트/그룹) | (secret) |
| `RUNNER_TAGS` | 러너 태그 | shell-71 |
| `DOCKER_GID` | 호스트 docker 그룹 GID (`getent group docker`로 확인) | 989 (검증 필요) |
| `DEPLOY_PORT_MIN` / `DEPLOY_PORT_MAX` | 자동 할당 포트 범위 | 9000 / 9099 |

- `.env`는 커밋 금지(`.gitignore`). `.env.example`만 커밋.
- `DOCKER_GID`는 서버마다 다름 — 셋업 시 `getent group docker`로 실측.

## 8. 검증 (Success Criteria)

무한 pending 정조준 체크리스트:
```
□ 러너 online(초록)         — GitLab UI / `gitlab-runner verify`
□ job tag ⊆ runner tags     — 불일치가 pending #1 원인
□ run_untagged=false 정합   — job에 태그 존재
□ 러너 not paused / 올바른 프로젝트에 locked
□ 러너 안에서 `docker ps` 성공 — 소켓/GID 권한 OK
□ examples/sample-app 스모크: 푸시 → 자동 포트 할당 → 컨테이너 running → curl 성공
□ 재배포: 같은 포트 유지 + 이전 컨테이너 교체 + **볼륨 데이터 보존** 확인
□ reset job: 데이터 초기화 + 서비스 재기동 확인
□ destroy job: 컨테이너 제거 + 포트 반납, **볼륨 보존** 확인
□ purge job: 컨테이너 + 볼륨 + 레지스트리 entry 전부 제거 확인
```

verification은 읽기가 아니라 **실행**으로 확인한다(스모크 파이프라인 green).

## 9. 다음 Phase (분리)

- **reconciler (Python)**: cron 주기로 GitLab API의 현존 프로젝트와 `registry.json`을 대조,
  GitLab에 없는 key에 대해 **`deploy-app --purge` 호출**(컨테이너 + 볼륨 + 포트 정리) →
  "repo 실삭제 시 데이터까지 자동 정리" 목표 충족.
  (`reconciler/` 디렉터리, GitLab API 토큰 사용. `python.md` 룰 적용.)
