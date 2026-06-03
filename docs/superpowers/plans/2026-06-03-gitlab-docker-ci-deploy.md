# GitLab Docker CI 자동 배포/삭제 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 71서버에 Docker로 GitLab CE + Runner를 기동하고, 공유 `deploy-app` 헬퍼로 푸시된 앱을 자동 할당 포트에 배포·교체·초기화·삭제한다.

**Architecture:** Runner는 컨테이너(shell executor)로 돌며 호스트 `docker.sock`을 마운트해 호스트 docker 데몬에 앱을 배포한다. 포트는 `registry.json`(flock 보호) 영속 매핑으로 프로젝트별 고정 할당. 배포 핵심 로직은 `scripts/lib/registry.sh`로 분리해 bats로 단위 검증한다.

**Tech Stack:** Bash, jq, docker / docker compose, gitlab-runner(shell executor), bats-core + shellcheck(테스트), GitLab CE.

**스펙:** `docs/superpowers/specs/2026-06-03-gitlab-docker-ci-deploy-design.md`

---

## File Structure

| 파일 | 책임 |
|------|------|
| `scripts/lib/registry.sh` | 순수 로직: 레지스트리 read/write, 빈 포트 탐색, 볼륨 파싱 (테스트 대상) |
| `scripts/deploy-app` | CI 진입점: 인자 파싱 → 포트 확보 → build/run/교체 + reset/destroy/purge |
| `scripts/clean_slate.sh` | 기존 gitlab/runner 컨테이너·볼륨 인벤토리 & 정리 (호스트 실행) |
| `scripts/register_runner.sh` | 러너 등록 (shell executor, tags, locked) (호스트 실행) |
| `runner/Dockerfile` | gitlab-runner + docker CLI + compose plugin + jq + deploy-app baked-in |
| `compose/gitlab.compose.yml` | GitLab CE 서비스 |
| `compose/runner.compose.yml` | Runner 서비스 (socket + GID + registry 볼륨) |
| `examples/sample-app/` | 데모 앱 + `.gitlab-ci.yml` (전체 체인 스모크) |
| `tests/registry.bats` | `registry.sh` 단위 테스트 |
| `tests/deploy-app.bats` | `deploy-app` 동작 테스트 (docker 스텁) |
| `.env.example` | 포트 범위, 토큰, 태그, docker GID, GitLab 호스트/포트 |

**검증 위치 구분:** Task 0–7의 로컬 검증(shellcheck/bats/`compose config`/`docker build`)은 개발 머신에서 실행. **러너 등록·전체 파이프라인·무한 pending 체크리스트(Task 8)는 71서버에서 수동 실행** — 로컬에서 PASS를 가장하지 않는다.

---

## Task 0: 사전 준비 & 테스트 하니스

**Files:**
- Modify: `.gitignore`
- Create: `tests/` (디렉터리)

- [ ] **Step 1: 필수 도구 설치 (개발 머신, macOS)**

Run:
```bash
brew install jq shellcheck bats-core
docker --version    # Docker Desktop 필요
```
Expected: 각 명령이 버전을 출력 (설치 확인).

- [ ] **Step 2: 러너 생성 파일을 gitignore에 추가**

`.gitignore` 끝에 추가:
```gitignore

# GitLab Runner (토큰 포함 — 커밋 금지)
runner/config.toml
```

- [ ] **Step 3: 커밋**

```bash
git add .gitignore
git commit -m "chore: ignore runner config.toml (contains token) — 러너 설정 gitignore"
```

---

## Task 1: 레지스트리/포트 로직 라이브러리 (TDD)

**Files:**
- Create: `scripts/lib/registry.sh`
- Test: `tests/registry.bats`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/registry.bats`:
```bash
#!/usr/bin/env bats
# registry.sh 순수 로직 단위 테스트.

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/lib/registry.sh"
  REG="$(mktemp)"; echo '{}' > "$REG"
}
teardown() { rm -f "$REG" "${REG}.lock"; }

@test "registry_port: 미등록 key는 빈 문자열" {
  run registry_port "$REG" "grp/app"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "registry_set 후 registry_port 왕복" {
  registry_set "$REG" "grp/app" 9000 "app" "single"
  run registry_port "$REG" "grp/app"
  [ "$output" -eq 9000 ]
}

@test "registry_type: 저장된 타입 반환" {
  registry_set "$REG" "grp/app" 9000 "app" "compose"
  run registry_type "$REG" "grp/app"
  [ "$output" = "compose" ]
}

@test "registry_remove: entry 삭제" {
  registry_set "$REG" "grp/app" 9000 "app" "single"
  registry_remove "$REG" "grp/app"
  run registry_port "$REG" "grp/app"
  [ -z "$output" ]
}

@test "port_in_registry: 할당된 포트 감지" {
  registry_set "$REG" "grp/app" 9000 "app" "single"
  run port_in_registry "$REG" 9000
  [ "$status" -eq 0 ]
}

@test "find_free_port: 레지스트리 점유 포트를 건너뜀" {
  registry_set "$REG" "grp/app" 9000 "app" "single"
  port_in_use() { return 1; }   # OS는 빈 것으로 스텁
  run find_free_port "$REG" 9000 9002
  [ "$output" -eq 9001 ]
}

@test "find_free_port: 범위 소진 시 실패" {
  registry_set "$REG" "a/a" 9000 "a" "single"
  port_in_use() { return 1; }
  run find_free_port "$REG" 9000 9000
  [ "$status" -ne 0 ]
}

@test "parse_volumes: namespaced -v 플래그 생성" {
  run parse_volumes "app" "data:/var/lib/app,cache:/cache"
  [ "$output" = "-v app_data:/var/lib/app -v app_cache:/cache" ]
}

@test "parse_volumes: 빈 spec은 빈 출력" {
  run parse_volumes "app" ""
  [ -z "$output" ]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/registry.bats`
Expected: FAIL (`scripts/lib/registry.sh` 없음 → source 실패).

- [ ] **Step 3: 최소 구현 작성**

`scripts/lib/registry.sh`:
```bash
#!/usr/bin/env bash
# registry.sh — 포트 영속 매핑(registry.json) 조회/갱신 + 빈 포트 탐색. jq 의존.
# 모든 조회/갱신 함수는 첫 인자로 registry 파일 경로를 받는다.

registry_init() {            # 파일 없으면 빈 객체 생성
  local f="$1"
  [ -f "$f" ] || echo '{}' > "$f"
}

registry_port() {            # key의 포트 출력 (없으면 빈 문자열)
  local f="$1" key="$2"
  jq -r --arg k "$key" '.[$k].port // empty' "$f"
}

registry_type() {            # key의 배포 타입(single|compose) 출력
  local f="$1" key="$2"
  jq -r --arg k "$key" '.[$k].type // empty' "$f"
}

registry_set() {             # key → {port, container, type} 기록
  local f="$1" key="$2" port="$3" container="$4" type="$5"
  local tmp; tmp="$(mktemp)"
  jq --arg k "$key" --argjson p "$port" --arg c "$container" --arg t "$type" \
    '.[$k] = {port:$p, container:$c, type:$t}' "$f" > "$tmp" && mv "$tmp" "$f"
}

registry_remove() {          # key 삭제
  local f="$1" key="$2"
  local tmp; tmp="$(mktemp)"
  jq --arg k "$key" 'del(.[$k])' "$f" > "$tmp" && mv "$tmp" "$f"
}

port_in_registry() {         # 레지스트리에 이미 할당된 포트면 0
  local f="$1" port="$2"
  jq -e --argjson p "$port" 'to_entries | any(.value.port == $p)' "$f" >/dev/null
}

port_in_use() {              # 호스트 docker가 해당 포트를 publish 중이면 0 (소켓 통해 호스트 데몬 조회)
  local port="$1"
  docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE "[:]${port}->"
}

find_free_port() {           # [min,max]에서 레지스트리·OS 모두 미사용인 첫 포트
  local f="$1" min="$2" max="$3" p
  for (( p=min; p<=max; p++ )); do
    if ! port_in_registry "$f" "$p" && ! port_in_use "$p"; then
      echo "$p"; return 0
    fi
  done
  echo "no free port in ${min}-${max}" >&2; return 1
}

parse_volumes() {            # "vol:/path,vol2:/p2" → "-v name_vol:/path -v name_vol2:/p2"
  local name="$1" spec="${2:-}"
  [ -n "$spec" ] || return 0
  local out="" item vol path items
  IFS=',' read -ra items <<< "$spec"
  for item in "${items[@]}"; do
    vol="${item%%:*}"; path="${item#*:}"
    out+=" -v ${name}_${vol}:${path}"
  done
  echo "${out# }"            # 선행 공백 제거
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bats tests/registry.bats`
Expected: 9 tests, all PASS.

- [ ] **Step 5: 린트**

Run: `shellcheck scripts/lib/registry.sh`
Expected: 경고 없음.

- [ ] **Step 6: 커밋**

```bash
git add scripts/lib/registry.sh tests/registry.bats
git commit -m "feat(deploy): add registry/port allocation lib with tests — 포트 레지스트리 로직+테스트"
```

---

## Task 2: deploy-app 진입점 (TDD)

**Files:**
- Create: `scripts/deploy-app`
- Test: `tests/deploy-app.bats`

- [ ] **Step 1: 실패하는 테스트 작성 (docker 스텁으로 호출 검증)**

`tests/deploy-app.bats`:
```bash
#!/usr/bin/env bats
# deploy-app 동작 테스트. PATH 앞단에 docker/ss 스텁을 두고 호출을 기록·검증.

setup() {
  BINDIR="$(mktemp -d)"; STATE="$(mktemp -d)"
  # docker 스텁: 호출을 calls.log에 기록.
  #  ps → 점유 포트 없음(빈 출력) / inspect → 컨테이너 running(true) / 그 외 성공.
  cat > "$BINDIR/docker" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STATE/calls.log"
case "\$1" in
  ps) exit 0 ;;
  inspect) echo "true"; exit 0 ;;
  volume) [ "\$2" = ls ] && echo "" ; exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BINDIR/docker"
  export PATH="$BINDIR:$PATH"
  export DEPLOY_REGISTRY="$STATE/registry.json"
  export DEPLOY_PORT_MIN=9000 DEPLOY_PORT_MAX=9000
  export CI_PROJECT_PATH="grp/sample" CI_COMMIT_SHORT_SHA="abc123"
}
teardown() { rm -rf "$BINDIR" "$STATE"; }

run_deploy() { run "$BATS_TEST_DIRNAME/../scripts/deploy-app" "$@"; }

@test "첫 배포: 빈 포트 할당 + build + run 호출" {
  run_deploy sample-app
  [ "$status" -eq 0 ]
  grep -q "build -t sample-app:abc123 ." "$STATE/calls.log"
  grep -q "run -d --name sample-app -p 9000:80" "$STATE/calls.log"
  [ "$(jq -r '.["grp/sample"].port' "$DEPLOY_REGISTRY")" -eq 9000 ]
}

@test "재배포: 기존 포트 재사용 + 컨테이너 교체(rm -f)" {
  run_deploy sample-app
  : > "$STATE/calls.log"
  run_deploy sample-app
  [ "$status" -eq 0 ]
  grep -q "rm -f sample-app" "$STATE/calls.log"
  grep -q "run -d --name sample-app -p 9000:80" "$STATE/calls.log"
}

@test "--destroy: 컨테이너 제거 + registry entry 삭제, 볼륨은 미제거" {
  run_deploy sample-app
  : > "$STATE/calls.log"
  run_deploy sample-app --destroy
  [ "$status" -eq 0 ]
  grep -q "rm -f sample-app" "$STATE/calls.log"
  ! grep -q "volume rm" "$STATE/calls.log"
  [ "$(jq -r '.["grp/sample"] // "gone"' "$DEPLOY_REGISTRY")" = "gone" ]
}

@test "--purge: 볼륨까지 제거 시도 + registry entry 삭제" {
  export DEPLOY_VOLUMES="data:/var/lib/app"
  run_deploy sample-app
  # 볼륨 목록 스텁이 항목을 반환하도록 교체
  cat > "$BINDIR/docker" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STATE/calls.log"
[ "\$1 \$2" = "volume ls" ] && { echo "sample-app_data"; exit 0; }
exit 0
EOF
  chmod +x "$BINDIR/docker"
  : > "$STATE/calls.log"
  run_deploy sample-app --purge
  [ "$status" -eq 0 ]
  grep -q "volume rm" "$STATE/calls.log"
  [ "$(jq -r '.["grp/sample"] // "gone"' "$DEPLOY_REGISTRY")" = "gone" ]
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bats tests/deploy-app.bats`
Expected: FAIL (`scripts/deploy-app` 없음).

- [ ] **Step 3: 최소 구현 작성**

`scripts/deploy-app`:
```bash
#!/usr/bin/env bash
# deploy-app — CI 공유 배포 헬퍼. 동적 포트 할당 + 교체/초기화/삭제.
# 사용: deploy-app <name> [--compose] [--reset|--destroy|--purge]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/registry.sh
source "$SCRIPT_DIR/lib/registry.sh"

REGISTRY="${DEPLOY_REGISTRY:-/srv/deploy/registry.json}"
PORT_MIN="${DEPLOY_PORT_MIN:-9000}"
PORT_MAX="${DEPLOY_PORT_MAX:-9099}"
APP_PORT="${APP_PORT:-80}"
COMPOSE_FILE="${DEPLOY_COMPOSE_FILE:-docker-compose.yml}"
KEY="${CI_PROJECT_PATH:?CI_PROJECT_PATH required}"

usage() { echo "usage: deploy-app <name> [--compose] [--reset|--destroy|--purge]" >&2; exit 2; }

name="${1:-}"; [ -n "$name" ] || usage; shift
action="deploy"; use_compose=0
while [ $# -gt 0 ]; do
  case "$1" in
    --compose) use_compose=1 ;;
    --reset)   action="reset" ;;
    --destroy) action="destroy" ;;
    --purge)   action="purge" ;;
    *) usage ;;
  esac
  shift
done

mkdir -p "$(dirname "$REGISTRY")"
registry_init "$REGISTRY"
# 동시 배포 직렬화. flock 없는 환경(로컬 mac 테스트)은 건너뜀 — 러너는 Linux라 항상 적용됨.
if command -v flock >/dev/null 2>&1; then exec 9>"${REGISTRY}.lock"; flock 9; fi

# destroy/purge는 저장된 타입으로 동작 분기
stored_type="$(registry_type "$REGISTRY" "$KEY")"
[ "$stored_type" = "compose" ] && use_compose=1

teardown_container() {
  if [ "$use_compose" -eq 1 ]; then
    COMPOSE_PROJECT_NAME="$name" docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
  else
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
}
teardown_volumes() {
  docker volume ls -q --filter "name=^${name}_" | xargs -r docker volume rm >/dev/null 2>&1 || true
}

if [ "$action" = "destroy" ]; then
  teardown_container; registry_remove "$REGISTRY" "$KEY"
  echo "destroyed $name (volumes preserved)"; exit 0
fi
if [ "$action" = "purge" ]; then
  teardown_container; teardown_volumes; registry_remove "$REGISTRY" "$KEY"
  echo "purged $name (container + volumes + registry)"; exit 0
fi
if [ "$action" = "reset" ]; then
  teardown_container; teardown_volumes    # 볼륨 비우고 아래에서 재배포
fi

# 포트 확보 (없으면 할당)
port="$(registry_port "$REGISTRY" "$KEY")"
if [ -z "$port" ]; then
  port="$(find_free_port "$REGISTRY" "$PORT_MIN" "$PORT_MAX")"
fi

if [ "$use_compose" -eq 1 ]; then
  registry_set "$REGISTRY" "$KEY" "$port" "$name" "compose"
  COMPOSE_PROJECT_NAME="$name" docker compose -f "$COMPOSE_FILE" up -d --build
else
  registry_set "$REGISTRY" "$KEY" "$port" "$name" "single"
  tag="${CI_COMMIT_SHORT_SHA:-latest}"
  docker build -t "${name}:${tag}" .
  docker rm -f "$name" >/dev/null 2>&1 || true     # 컨테이너만 교체 (볼륨 유지)
  # shellcheck disable=SC2046  # parse_volumes 출력은 의도적 단어 분할
  docker run -d --name "$name" -p "${port}:${APP_PORT}" \
    $(parse_volumes "$name" "${DEPLOY_VOLUMES:-}") \
    --restart unless-stopped "${name}:${tag}"
fi

# 검증: 컨테이너 running 확인 (호스트 docker 기준 — 러너 netns와 무관). 최대 10초.
verify_running() {
  if [ "$use_compose" -eq 1 ]; then
    COMPOSE_PROJECT_NAME="$name" docker compose -f "$COMPOSE_FILE" ps --status running -q | grep -q .
  else
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = "true" ]
  fi
}
for _ in $(seq 1 10); do verify_running && break; sleep 1; done
verify_running || { echo "deploy failed: $name not running" >&2; exit 1; }
echo "deployed $name -> :${port}"
```

- [ ] **Step 4: 실행 권한 부여 후 테스트 통과 확인**

Run:
```bash
chmod +x scripts/deploy-app
bats tests/deploy-app.bats
```
Expected: 4 tests, all PASS.

- [ ] **Step 5: 린트**

Run: `shellcheck scripts/deploy-app`
Expected: 경고 없음 (SC2046은 인라인 disable 처리됨).

- [ ] **Step 6: 커밋**

```bash
git add scripts/deploy-app tests/deploy-app.bats
git commit -m "feat(deploy): add deploy-app helper (deploy/reset/destroy/purge) — 배포 헬퍼+테스트"
```

---

## Task 3: Runner 이미지 (deploy-app baked-in)

**Files:**
- Create: `runner/Dockerfile`

- [ ] **Step 1: Dockerfile 작성**

`runner/Dockerfile`:
```dockerfile
# syntax=docker/dockerfile:1
# gitlab-runner + docker CLI + compose plugin + jq, deploy-app/lib 포함.
# shell executor 가 호스트 docker.sock 으로 호스트에 배포한다.
FROM gitlab/gitlab-runner:latest

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      docker.io docker-compose-v2 jq

COPY scripts/lib/registry.sh /usr/local/lib/deploy/registry.sh
COPY scripts/deploy-app /usr/local/bin/deploy-app
RUN chmod +x /usr/local/bin/deploy-app
```

> `deploy-app`은 `$SCRIPT_DIR/lib/registry.sh`를 source 한다. 이미지에서는 `/usr/local/bin/lib/registry.sh` 경로가 되도록 심볼릭 처리.

- [ ] **Step 2: lib 경로 정합 — Dockerfile에 심링크 추가**

`runner/Dockerfile` 끝에 추가:
```dockerfile
RUN mkdir -p /usr/local/bin/lib && \
    ln -sf /usr/local/lib/deploy/registry.sh /usr/local/bin/lib/registry.sh
```

- [ ] **Step 3: 빌드**

Run: `docker build -f runner/Dockerfile -t gitlab-runner-deploy:test .`
Expected: 빌드 성공.

- [ ] **Step 4: 이미지 내 도구·헬퍼 스모크**

Run:
```bash
docker run --rm gitlab-runner-deploy:test sh -c 'docker --version && jq --version && deploy-app 2>&1 | head -1'
```
Expected: docker/jq 버전 출력 + `deploy-app`의 usage 메시지(인자 없음 → exit 2, usage 출력).

- [ ] **Step 5: 커밋**

```bash
git add runner/Dockerfile
git commit -m "feat(runner): build runner image with docker CLI + deploy-app — 러너 이미지"
```

---

## Task 4: GitLab CE compose + .env.example

**Files:**
- Create: `compose/gitlab.compose.yml`
- Create: `.env.example`

- [ ] **Step 1: .env.example 작성**

`.env.example`:
```dotenv
# === GitLab ===
GITLAB_HOSTNAME=gitlab.71.internal   # external_url 호스트 (서버 IP/도메인)
GITLAB_HTTP_PORT=8929                # GitLab 웹 포트
GITLAB_SSH_PORT=2289                 # GitLab SSH 포트

# === Runner ===
CI_SERVER_URL=http://gitlab.71.internal:8929
RUNNER_TOKEN=                        # 프로젝트/그룹 러너 등록 토큰 (커밋 금지)
RUNNER_TAGS=shell-71                 # job tags 와 일치해야 함
DOCKER_GID=989                       # 호스트 docker 그룹 GID — `getent group docker`로 실측

# === 배포 포트 범위 ===
DEPLOY_PORT_MIN=9000
DEPLOY_PORT_MAX=9099
```

- [ ] **Step 2: GitLab compose 작성**

`compose/gitlab.compose.yml`:
```yaml
# GitLab CE — 71서버 운영 인스턴스. 데이터는 named 볼륨에 영속.
services:
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: unless-stopped
    hostname: ${GITLAB_HOSTNAME}
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${GITLAB_HOSTNAME}:${GITLAB_HTTP_PORT}'
        gitlab_rails['gitlab_shell_ssh_port'] = ${GITLAB_SSH_PORT}
    ports:
      - "${GITLAB_HTTP_PORT}:${GITLAB_HTTP_PORT}"
      - "${GITLAB_SSH_PORT}:22"
    volumes:
      - gitlab_config:/etc/gitlab
      - gitlab_logs:/var/log/gitlab
      - gitlab_data:/var/opt/gitlab
    shm_size: "256m"

volumes:
  gitlab_config:
  gitlab_logs:
  gitlab_data:
```

- [ ] **Step 3: compose 문법·환경 보간 검증**

Run: `docker compose --env-file .env.example -f compose/gitlab.compose.yml config`
Expected: 보간된 최종 설정 출력, 에러 없음.

- [ ] **Step 4: 커밋**

```bash
git add compose/gitlab.compose.yml .env.example
git commit -m "feat(gitlab): add GitLab CE compose + env template — GitLab compose"
```

---

## Task 5: Runner compose (socket + GID + registry 볼륨)

**Files:**
- Create: `compose/runner.compose.yml`

- [ ] **Step 1: Runner compose 작성**

`compose/runner.compose.yml`:
```yaml
# GitLab Runner — Task 3 이미지를 빌드해 기동.
# 호스트 docker.sock 마운트 + docker 그룹 GID 로 호스트 docker 데몬 제어.
# /srv/deploy 는 registry.json 영속 저장 위치(호스트 공유).
services:
  runner:
    build:
      context: ..
      dockerfile: runner/Dockerfile
    image: gitlab-runner-deploy:latest
    container_name: gitlab-runner
    restart: unless-stopped
    group_add:
      - "${DOCKER_GID}"            # 호스트 docker 그룹 GID — 소켓 접근 권한
    environment:
      DEPLOY_PORT_MIN: ${DEPLOY_PORT_MIN}
      DEPLOY_PORT_MAX: ${DEPLOY_PORT_MAX}
      DEPLOY_REGISTRY: /srv/deploy/registry.json
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - runner_config:/etc/gitlab-runner
      - /srv/deploy:/srv/deploy

volumes:
  runner_config:
```

> 러너 컨테이너는 기본 root로 동작하므로 소켓 접근은 가능하나, `group_add`로 GID를 명시해 비-root 전환 시에도 동작하도록 한다. 배포 검증은 호스트 docker(`docker inspect`/`docker compose ps`)로 하므로 러너에 `network_mode: host`는 불필요하다.

- [ ] **Step 2: compose 문법·환경 보간 검증**

Run: `docker compose --env-file .env.example -f compose/runner.compose.yml config`
Expected: `group_add`에 GID 보간, 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add compose/runner.compose.yml
git commit -m "feat(runner): add runner compose with socket+GID mounts — 러너 compose"
```

---

## Task 6: clean_slate / register_runner 스크립트

**Files:**
- Create: `scripts/clean_slate.sh`
- Create: `scripts/register_runner.sh`

- [ ] **Step 1: clean_slate.sh 작성**

`scripts/clean_slate.sh`:
```bash
#!/usr/bin/env bash
# clean_slate.sh — 기존 gitlab/gitlab-runner 컨테이너·볼륨·네트워크 인벤토리 후 정리.
# 무한 pending 의 흔한 원인인 옛 러너 등록 잔재를 제거한다. 확인 프롬프트 포함.
set -euo pipefail

echo "=== 현재 gitlab/runner 관련 리소스 ==="
echo "[containers]"; docker ps -a --filter "name=gitlab" --format '  {{.Names}}\t{{.Status}}'
echo "[volumes]";    docker volume ls --filter "name=gitlab" --format '  {{.Name}}'
echo "[networks]";   docker network ls --filter "name=gitlab" --format '  {{.Name}}'

read -r -p "위 gitlab/gitlab-runner 컨테이너를 중지·삭제할까요? (y/N) " ans
[ "$ans" = "y" ] || { echo "취소됨 (리소스 유지)"; exit 0; }

docker rm -f gitlab gitlab-runner 2>/dev/null || true
echo "컨테이너 정리 완료. 볼륨은 데이터 보존 위해 수동 확인:"
echo "  docker volume rm gitlab_config gitlab_logs gitlab_data runner_config   # 필요 시"
```

- [ ] **Step 2: register_runner.sh 작성**

`scripts/register_runner.sh`:
```bash
#!/usr/bin/env bash
# register_runner.sh — 러너를 shell executor 로 등록. 프로젝트 전용 + 태그 강제.
# .env 의 CI_SERVER_URL / RUNNER_TOKEN / RUNNER_TAGS 사용. 71서버에서 실행.
set -euo pipefail

: "${CI_SERVER_URL:?set CI_SERVER_URL}"
: "${RUNNER_TOKEN:?set RUNNER_TOKEN}"
: "${RUNNER_TAGS:?set RUNNER_TAGS}"

docker exec gitlab-runner gitlab-runner register --non-interactive \
  --url "$CI_SERVER_URL" \
  --token "$RUNNER_TOKEN" \
  --executor shell \
  --tag-list "$RUNNER_TAGS" \
  --run-untagged=false \
  --locked=true

echo "등록 완료. 확인: docker exec gitlab-runner gitlab-runner verify"
```

- [ ] **Step 3: 린트**

Run: `shellcheck scripts/clean_slate.sh scripts/register_runner.sh`
Expected: 경고 없음.

- [ ] **Step 4: 실행 권한 + 커밋**

```bash
chmod +x scripts/clean_slate.sh scripts/register_runner.sh
git add scripts/clean_slate.sh scripts/register_runner.sh
git commit -m "feat(scripts): add clean_slate + register_runner — 정리·러너등록 스크립트"
```

---

## Task 7: 데모 앱 + .gitlab-ci.yml

**Files:**
- Create: `examples/sample-app/Dockerfile`
- Create: `examples/sample-app/index.html`
- Create: `examples/sample-app/.gitlab-ci.yml`

- [ ] **Step 1: 데모 앱 작성**

`examples/sample-app/index.html`:
```html
<!doctype html><meta charset="utf-8"><title>sample-app</title>
<h1>sample-app deployed via GitLab CI</h1>
```

`examples/sample-app/Dockerfile`:
```dockerfile
# syntax=docker/dockerfile:1
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

- [ ] **Step 2: .gitlab-ci.yml 작성**

`examples/sample-app/.gitlab-ci.yml`:
```yaml
# 전체 체인 스모크: 푸시 → 자동 포트 할당 → 배포. 수동 reset/destroy/purge.
variables:
  APP_PORT: "80"

stages: [deploy]

deploy:
  stage: deploy
  tags: [shell-71]                            # 러너 태그와 일치 (불일치 = 무한 pending)
  rules:
    - if: $CI_COMMIT_REF_PROTECTED == "true"  # protected branch 에서만
  script:
    - deploy-app sample-app                    # 재배포: 데이터 보존

reset:
  stage: deploy
  tags: [shell-71]
  when: manual
  script:
    - deploy-app sample-app --reset            # 데이터 초기화

destroy:
  stage: deploy
  tags: [shell-71]
  when: manual
  script:
    - deploy-app sample-app --destroy          # 서비스만 내림 (데이터 보존)

purge:
  stage: deploy
  tags: [shell-71]
  when: manual
  script:
    - deploy-app sample-app --purge            # 데이터 포함 완전 삭제
```

- [ ] **Step 3: 데모 앱 빌드 검증**

Run: `docker build -t sample-app:smoke examples/sample-app`
Expected: 빌드 성공.

- [ ] **Step 4: 커밋**

```bash
git add examples/sample-app
git commit -m "feat(examples): add sample-app with deploy/reset/destroy/purge ci — 데모 앱+ci"
```

---

## Task 8: README setup 섹션 + 71서버 검증 런북

**Files:**
- Modify: `README.md`
- Create: `docs/RUNBOOK.md`

- [ ] **Step 1: README에 setup 명령 추가**

`README.md`의 `## 상태` 섹션을 아래로 교체:
```markdown
## 셋업 (71서버)

```bash
cp .env.example .env          # 값 채우기 (GID는 `getent group docker`로 확인)
docker compose --env-file .env -f compose/gitlab.compose.yml up -d   # GitLab
docker compose --env-file .env -f compose/runner.compose.yml up -d   # Runner
bash scripts/register_runner.sh                                      # 러너 등록
```

GitLab UI → 프로젝트/그룹 CI/CD → Runners 에서 토큰을 발급해 `.env`의 `RUNNER_TOKEN`에 넣는다.
앱 repo에는 `examples/sample-app/.gitlab-ci.yml`을 참고한 `.gitlab-ci.yml`을 둔다.
전체 검증 절차는 [`docs/RUNBOOK.md`](docs/RUNBOOK.md).
```

- [ ] **Step 2: 검증 런북 작성 (무한 pending 정조준)**

`docs/RUNBOOK.md`:
```markdown
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
```

- [ ] **Step 3: 커밋**

```bash
git add README.md docs/RUNBOOK.md
git commit -m "docs: add setup section + 71-server verification runbook — 셋업·검증 런북"
```

---

## 다음 Phase (이 계획 범위 밖)

reconciler(Python): cron으로 GitLab API ↔ `registry.json` 대조, 사라진 프로젝트에 `deploy-app --purge` 자동 호출. 별도 spec → plan으로 진행.
