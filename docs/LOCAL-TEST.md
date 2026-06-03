# 로컬(mac Docker Desktop)에서 GitLab UI로 자동 배포 테스트

71서버 없이, 로컬에서 GitLab+Runner를 띄우고 **UI에서 푸시→자동 포트 배포**까지 재현한다.
서버 검증(`docs/RUNBOOK.md`)의 로컬 버전. 서버용 compose는 그대로 두고
`compose/runner.local.yml` 오버라이드를 덧댄다.

## 사전 준비

1. **Docker Desktop 메모리 ≥ 6GB** (Settings → Resources). GitLab CE는 무겁다 — 부족하면 기동 실패/극저속.
2. **hosts 등록** — 브라우저와 러너가 같은 호스트명을 쓰도록:
   ```bash
   echo "127.0.0.1 gitlab.local" | sudo tee -a /etc/hosts
   ```

## 1. .env 작성 (로컬 값)

```bash
cp .env.example .env
```
`.env`를 아래로 수정:
```dotenv
GITLAB_HOSTNAME=gitlab.local
GITLAB_HTTP_PORT=8929
GITLAB_SSH_PORT=2289
CI_SERVER_URL=http://gitlab.local:8929
RUNNER_TOKEN=                      # 4단계에서 UI 토큰으로 채움
RUNNER_TAGS=shell-71
DOCKER_GID=0                       # mac: 러너는 root로 동작 → 0(root group)으로 충분
DEPLOY_PORT_MIN=9000
DEPLOY_PORT_MAX=9099
```

## 2. GitLab 기동

```bash
docker compose --env-file .env -f compose/gitlab.compose.yml up -d
```
초기화에 3~5분. 준비 확인:
```bash
docker logs -f gitlab        # "gitlab Reconfigured!" 보이면 완료 (Ctrl-C)
```
브라우저 → http://gitlab.local:8929 . root 초기 비밀번호:
```bash
docker exec gitlab cat /etc/gitlab/initial_root_password   # 24시간 내 유효
```
`root` / 위 비밀번호로 로그인.

## 3. 프로젝트 생성 + 코드 준비

1. UI에서 **New project → Create blank project** (이름: `sample-app`, Initialize with README 체크 해제).
2. 로컬에서 데모 앱을 그 프로젝트로 푸시 (별도 폴더에서):
   ```bash
   mkdir /tmp/sample-app && cd /tmp/sample-app
   cp -r <이 repo>/examples/sample-app/. .     # Dockerfile, index.html, .gitlab-ci.yml
   git init -b main
   git remote add origin http://gitlab.local:8929/root/sample-app.git
   git add . && git commit -m "init sample-app"
   # 아직 push 안 함 — 러너부터 등록(4단계)
   ```

## 4. 러너 등록

1. UI → 프로젝트 `sample-app` → **Settings → CI/CD → Runners → New project runner**.
   - Tags: `shell-71` 입력
   - **"Run untagged jobs" 체크 해제** (태그 강제)
   - Create → 표시되는 **authentication token**(`glrt-...`) 복사.
2. `.env`의 `RUNNER_TOKEN=glrt-...` 에 붙여넣기.
3. 러너 컨테이너 기동 + 등록:
   ```bash
   docker compose --env-file .env -f compose/runner.compose.yml -f compose/runner.local.yml up -d --build
   docker exec -e CI_SERVER_URL -e RUNNER_TOKEN -e RUNNER_TAGS gitlab-runner true 2>/dev/null || true
   set -a; source .env; set +a          # register 스크립트가 쓸 env 로드
   bash scripts/register_runner.sh
   docker exec gitlab-runner gitlab-runner verify     # online 확인
   ```
   UI Runners 목록에 초록불(online)로 떠야 한다.

## 5. 푸시 → 자동 배포 확인

```bash
cd /tmp/sample-app
git push -u origin main      # main은 기본 protected → deploy job 실행 조건 충족
```
- UI → 프로젝트 → **Build → Pipelines** 에서 `deploy` job 로그 확인. green이면 성공.
- 할당된 포트 확인:
  ```bash
  docker exec gitlab-runner cat /srv/deploy/registry.json
  # {"root/sample-app":{"port":9000,"container":"sample-app","type":"single"}}
  ```
- 배포 확인: `curl http://localhost:9000` → sample-app HTML.

## 6. 라이프사이클 (UI 수동 job)

파이프라인 화면에서 수동 job 실행:
- **reset** → 데이터 초기화 후 재기동
- **destroy** → 컨테이너 내려감(볼륨 보존): `docker ps`로 사라짐 확인
- **purge** → 컨테이너+볼륨+레지스트리 entry 제거: registry.json에서 entry 사라짐

## 무한 pending 디버깅 (원래 막혔던 지점)

job이 pending에서 안 넘어가면:
- [ ] UI Runners에 러너 online(초록)? 아니면 `docker logs gitlab-runner`
- [ ] job `tags: [shell-71]` == 러너 tags? (불일치가 1순위 원인)
- [ ] 러너 "Run untagged" 꺼져있고 job에 태그 있음?
- [ ] 러너가 GitLab에 도달? `docker exec gitlab-runner curl -sI http://gitlab.local:8929` (host-gateway 확인)
- [ ] 러너가 docker 소켓 접근? `docker exec gitlab-runner docker ps`

## 정리

```bash
docker compose --env-file .env -f compose/runner.compose.yml -f compose/runner.local.yml down
docker compose --env-file .env -f compose/gitlab.compose.yml down
# 데이터까지: 위에 -v 추가 (gitlab 볼륨/registry 볼륨 삭제)
```
