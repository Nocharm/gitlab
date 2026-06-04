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

## 6. 라이프사이클 (UI 수동 job)
**reset**(데이터 초기화) / **destroy**(서비스만 내림, 볼륨 보존) / **purge**(완전 삭제).

## 무한 pending 체크리스트
- [ ] UI Runners online(초록)? 아니면 `docker logs --tail 30 gitlab-runner`
- [ ] job `tags:[shell-71]` == 러너 tags? (불일치 = 1순위)
- [ ] 러너 "Run untagged" 꺼짐 + job에 태그?
- [ ] 러너→GitLab 도달(4단계 health 200) / 러너→소켓(socket OK)?

## 정리
```bash
docker compose --env-file .env -f compose/runner.compose.yml down
docker compose --env-file .env -f compose/gitlab.compose.yml down
# 데이터까지: 위에 -v 추가
```
