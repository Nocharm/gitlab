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
