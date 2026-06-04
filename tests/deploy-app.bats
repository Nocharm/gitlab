#!/usr/bin/env bats
# deploy-app 동작 테스트. PATH 앞단에 docker 스텁을 두고 호출을 기록·검증.

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

@test "포트 점유 시 다음 빈 포트로 재시도" {
  export DEPLOY_PORT_MIN=9000 DEPLOY_PORT_MAX=9002
  # docker 스텁: run -p 9000 은 점유 에러, 그 외 포트는 성공
  cat > "$BINDIR/docker" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$STATE/calls.log"
case "\$1" in
  ps) exit 0 ;;
  inspect) echo "true"; exit 0 ;;
  run)
    case "\$*" in
      *"-p 9000:"*) echo "Bind for 0.0.0.0:9000 failed: port is already allocated" >&2; exit 1 ;;
      *) exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BINDIR/docker"
  run_deploy sample-app
  [ "$status" -eq 0 ]
  grep -q "run -d --name sample-app -p 9001:80" "$STATE/calls.log"
  [ "$(jq -r '.["grp/sample"].port' "$DEPLOY_REGISTRY")" -eq 9001 ]
}
