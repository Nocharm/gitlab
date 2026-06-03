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
