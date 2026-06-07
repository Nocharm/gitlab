# 서버 배포 런북

사내 서버 배포 절차. **실제 호스트·포트·GID는 서버의 `.env`에만** 둔다(커밋 금지).
아래 명령은 `.env`를 읽어 동작하므로 값 하드코딩이 없다. 각 단계는 짧은 성공 표시를 낸다.

> 전제: 이 repo가 서버에 올라가 있고 그 안에서 실행. 실행 계정이 docker 그룹에 속해야 한다.
> 먼저 한 번: `set -a; source .env; set +a` (현재 셸에 .env 로드).

## 0. (재셋업 시) 기존 잔재 정리
```bash
bash scripts/clean_slate.sh
```

## 1. .env 확인
```bash
cp .env.example .env        # 최초 1회. 그 뒤 실제 값으로 채운다
getent group docker         # docker:x:<GID>:...  → 이 <GID>를 .env 의 DOCKER_GID 에
set -a; source .env; set +a
echo "host=$GITLAB_HOSTNAME web=$GITLAB_HTTP_PORT gid=$DOCKER_GID range=$DEPLOY_PORT_MIN-$DEPLOY_PORT_MAX"
```

> Windows 경유로 받았다면 `.env`가 CRLF일 수 있다: `tr -d '\r' < .env > .env.new && mv .env.new .env`.

## 1.5 배포 상태 디렉터리 준비 (필수, 1회)
`registry.json`이 사는 `/srv/deploy`를 배포 job(=`gitlab-runner` 유저)이 쓸 수 있어야 한다:
```bash
sudo mkdir -p /srv/deploy && sudo chmod 777 /srv/deploy
```
> 안 하면 배포 job이 `registry.json: permission denied` 로 실패한다.

## 2. GitLab 기동
```bash
docker compose --env-file .env -f compose/gitlab.compose.yml up -d
```
초기화 3~5분. 준비 확인 (302/200 뜨면 됨):
```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://localhost:${GITLAB_HTTP_PORT}/users/sign_in"
```
root 초기 비밀번호 → 브라우저 `http://$GITLAB_HOSTNAME:$GITLAB_HTTP_PORT` 로 `root` 로그인:
```bash
docker exec gitlab cat /etc/gitlab/initial_root_password | grep Password   # 24h 유효
```

## 3. 러너 생성 + 토큰
UI → **Admin → CI/CD → Runners → New instance runner** → Tags `shell-71`, "Run untagged" 해제 → Create.
토큰(`glrt-...`) 복사. **토큰 페이지가 에러나면**(GitLab 19.x UI 버그) 콘솔로 추출:
```bash
docker exec gitlab gitlab-rails runner 'puts Ci::Runner.last.token'
```
→ `.env` 의 `RUNNER_TOKEN=glrt-...` 기입 후 `set -a; source .env; set +a` 다시.

## 4. 러너 기동 + 등록
```bash
docker compose --env-file .env -f compose/runner.compose.yml up -d --build
bash scripts/register_runner.sh
docker exec gitlab-runner gitlab-runner verify                                  # online
docker exec gitlab-runner curl -s -o /dev/null -w '%{http_code}\n' "http://${GITLAB_HOSTNAME}:${GITLAB_HTTP_PORT}/-/health"   # 200 = GitLab 도달
docker exec gitlab-runner docker ps >/dev/null && echo "socket OK"             # 소켓 접근
```

## 5. 프로젝트 push → 자동 배포
1. UI에서 blank project 생성(예: `sample-app`, README 체크 해제).
2. 데모 앱 push:
   ```bash
   cd /tmp && rm -rf sample-app && cp -r "$OLDPWD/examples/sample-app" sample-app && cd sample-app
   git init -b main
   git remote add origin "http://${GITLAB_HOSTNAME}:${GITLAB_HTTP_PORT}/root/sample-app.git"
   git add . && git commit -m "init sample-app"
   git push -u origin main          # main=protected → deploy job 실행
   ```
3. UI → 프로젝트 → **Build → Pipelines** 에서 `deploy` job green.
4. 할당 포트 + 배포 확인:
   ```bash
   cat /srv/deploy/registry.json                         # {"root/sample-app":{"port":<P>,...}}
   P=$(jq -r '.["root/sample-app"].port' /srv/deploy/registry.json)
   curl -s "http://localhost:$P" | head -1               # sample-app HTML
   ```

## 선택: Keycloak SSO 연동 (OIDC)

기존 유저·데이터를 **건드리지 않고** 로그인 수단만 추가한다. 패스워드 로그인은 병행 유지되므로
설정이 틀려도 락아웃되지 않는다.

1. **Keycloak**: realm에 client 생성(Client authentication=ON=confidential).
   Valid Redirect URIs 에 콜백 추가:
   ```
   http://<GITLAB_HOSTNAME>:<GITLAB_HTTP_PORT>/users/auth/openid_connect/callback
   ```
   Credentials 탭에서 client secret 복사.
2. **`.env`** 채우기(커밋 금지):
   ```bash
   KEYCLOAK_ISSUER=https://<keycloak>/realms/<realm>
   KEYCLOAK_CLIENT_ID=gitlab
   KEYCLOAK_CLIENT_SECRET=<위 secret>
   ```
   > ⚠️ 빈 값 줄에는 인라인 주석(`KEY=  # ...`)을 쓰지 말 것 — compose가 주석을 값으로 읽는다.
3. **반영**(데이터 볼륨 보존, 컨테이너만 재생성):
   ```bash
   set -a; source .env; set +a
   docker compose --env-file .env -f compose/gitlab.compose.yml up -d   # env 변경 감지 → 재생성
   ```
   GitLab 로그인 화면에 **"Keycloak"** 버튼이 뜨면 성공.
4. **유저 동작**:
   - 기존 유저 = 이메일이 일치하면 자동 연결(`omniauth_auto_link_user`). 계정 그대로.
   - 처음 보는 외부 유저 = 관리자 승인 전까지 차단(`omniauth_block_auto_created_users=true`).
     **Admin → Users**에서 승인. 이 정책을 바꾸려면 `gitlab.compose.yml`의 해당 옵션 수정.

## 6. 라이프사이클 (UI 수동 job)
**reset**(데이터 초기화) / **destroy**(서비스만 내림, 볼륨 보존) / **purge**(완전 삭제).

## 무한 pending 체크리스트
- [ ] UI Runners online(초록)? 아니면 `docker logs --tail 30 gitlab-runner`
- [ ] job `tags:[shell-71]` == 러너 tags? (불일치 = 1순위)
- [ ] 러너 "Run untagged" 꺼짐 + job에 태그?
- [ ] 러너→GitLab 도달(4단계 health 200) / 러너→소켓(socket OK)?

## 트러블슈팅 (실제 겪은 이슈 → 해결)

| 증상 | 원인 | 해결 |
|---|---|---|
| `bash: $'\r'` / `/usr/bin/env: 'bash\r'` | 스크립트·`.env`가 CRLF(Windows 경유) | `tr -d '\r' < f > f.t && mv f.t f`. 이미지 안 deploy-app은 Dockerfile이 빌드 때 자동 LF 변환. 근본적으론 사내 PC에서 **fresh clone**(아래) |
| 배포 job `registry.json: permission denied` | `/srv/deploy`가 root 소유, job은 비-root | `sudo chmod 777 /srv/deploy` (1.5단계) |
| 배포 job `docker.sock: permission denied` | job이 `gitlab-runner`(비-root) 유저로 도는데 그 유저가 docker GID 그룹에 없음 | Dockerfile이 `gitlab-runner`를 `DOCKER_GID` 그룹에 추가(build arg). `.env`의 DOCKER_GID를 `getent group docker` 값과 맞추고 `up -d --build`. 확인: `docker exec gitlab-runner id gitlab-runner` 에 그 GID |
| `register` FATAL: `--locked/--tag-list ... is reserved` | GitLab 16.6+ 토큰 등록은 url/token/executor만 허용 | `register_runner.sh`에서 해당 옵션 제거됨. 태그 등은 UI 러너 생성 시 설정 |
| 러너 생성 후 토큰 상세페이지 에러 | GitLab 19.x 프론트엔드 버그(서버는 정상) | 콘솔로 토큰 추출: `docker exec gitlab gitlab-rails runner 'puts Ci::Runner.last.token'` |
| `WARN Found orphan container (gitlab)` | 두 compose가 같은 프로젝트로 인식 | 무해. **`--remove-orphans` 절대 금지**(GitLab 컨테이너 삭제됨) |
| `the url needs to be entered` / `PANIC: ... EOF` | `$CI_SERVER_URL` 미설정 / 여러 줄 `\`이 전송 중 깨짐 | `set -a; source .env; set +a` 재실행 / register 명령을 **한 줄로** |

### Windows 경유 전송 시 CRLF 최소화
- **가장 깨끗:** 사내 PC에서 **fresh `git clone`** (기존 클론에 `git pull`하면 안 바뀐 파일은 CRLF 유지됨). `.gitattributes(eol=lf)`로 전부 LF가 된다.
- 전송 시 `rsync ... --exclude '.env'` 로 서버의 정리된 `.env`를 유지.
- 이미지 안 스크립트(deploy-app/registry.sh)는 Dockerfile이 빌드 때 자동 LF 변환 → 재빌드만 하면 된다.

## 정리
```bash
docker compose --env-file .env -f compose/runner.compose.yml down
docker compose --env-file .env -f compose/gitlab.compose.yml down
# 데이터까지: 위에 -v 추가
```
