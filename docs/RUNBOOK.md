# 71서버 검증 런북

> 로컬에서 가짜 PASS 불가 — 아래는 71서버에서 실제 실행해 확인한다.

## 0. clean slate (재셋업 시)
```bash
bash scripts/clean_slate.sh
```

## 1. 기동 & 러너 등록
```bash
docker compose --env-file .env -f compose/gitlab.compose.yml up -d
docker compose --env-file .env -f compose/runner.compose.yml up -d
getent group docker        # DOCKER_GID 실측해 .env 와 일치 확인
bash scripts/register_runner.sh
docker exec gitlab-runner gitlab-runner verify   # online 확인
```

## 2. 무한 pending 체크리스트
- [ ] GitLab UI에서 러너 online(초록)
- [ ] job `tags: [shell-71]` ⊆ 러너 tags (불일치 = pending #1 원인)
- [ ] 러너 `run_untagged=false`인데 job에 태그 존재
- [ ] 러너 not paused / 올바른 프로젝트에 locked
- [ ] `docker exec gitlab-runner docker ps` 성공 (소켓/GID 권한 OK)

## 3. 전체 체인 스모크
- [ ] sample-app repo의 protected branch에 푸시 → `deploy` job green
- [ ] `registry.json`에 `grp/sample` 포트 기록됨: `cat /srv/deploy/registry.json`
- [ ] `curl http://localhost:<할당포트>` → sample-app HTML 응답
- [ ] 재푸시 → 같은 포트 유지 + 컨테이너 교체 확인
- [ ] `reset` 수동 job → 데이터 초기화 + 서비스 재기동
- [ ] `destroy` 수동 job → 컨테이너 제거 + 볼륨 보존(`docker volume ls`)
- [ ] `purge` 수동 job → 컨테이너 + 볼륨 + registry entry 제거
