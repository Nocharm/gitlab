#!/usr/bin/env bash
# probe-issuer.sh — Keycloak OIDC issuer/경로 진단 헬퍼 (서버에서 pull 후 실행만).
# GitLab 컨테이너 안에서 Keycloak 을 여러 경로로 찔러 realm 존재·SSL 리다이렉트·issuer 를 한 번에 본다.
# 왜: OIDC 로그인이 SSL/경로 오설정으로 깨질 때 .env 의 KEYCLOAK_ISSUER 정답값을 확정하려고.
# 사용: bash docs/keycloak/probe-issuer.sh
set -uo pipefail   # -e 제외: 진단이라 일부 curl 실패해도 계속 진행

# --- 환경 (이 서버 토폴로지) ---
KC_BASE="http://182.199.63.71:8080"   # Keycloak (71서버, http)
REALM="gitlab"
# 참고: GitLab 외부 URL = g-ai-agent.sbiologics.com:2222 (Keycloak client redirect_uri /
#       .env 의 GITLAB_HOSTNAME:GITLAB_HTTP_PORT 용. issuer 와는 별개)

ex() { docker exec gitlab bash -c "$1"; }   # curl 을 GitLab 컨테이너 안에서 실행 = 실제 OIDC 주체

show() {                                    # $1=라벨 $2=url [follow옵션]
  local label="$1" url="$2" follow="${3:-}"
  local out
  out="$(ex "curl -sS -m 8 ${follow} -o /dev/null -w '%{http_code}   redirect=%{redirect_url}   final=%{url_effective}' '$url'" 2>&1)"
  printf '  %-12s %s\n' "$label" "$out"
}

echo "== Keycloak 진단 (base=${KC_BASE} realm=${REALM}) =="

echo "[A] 신버전 경로:"
show "root"      "${KC_BASE}/"
show "realm"     "${KC_BASE}/realms/${REALM}"
show "discovery" "${KC_BASE}/realms/${REALM}/.well-known/openid-configuration"

echo "[B] 구버전 /auth 경로:"
show "realm"     "${KC_BASE}/auth/realms/${REALM}"
show "discovery" "${KC_BASE}/auth/realms/${REALM}/.well-known/openid-configuration"

echo "[C] 리다이렉트 따라가 최종(-L):"
show "disc-new"  "${KC_BASE}/realms/${REALM}/.well-known/openid-configuration" "-L"
show "disc-auth" "${KC_BASE}/auth/realms/${REALM}/.well-known/openid-configuration" "-L"

echo "[D] issuer 추출 시도(-L, 둘 중 되는 쪽):"
issuer="$(ex "curl -sSL -m 8 '${KC_BASE}/realms/${REALM}/.well-known/openid-configuration'" 2>/dev/null | grep -o '"issuer":"[^"]*"')"
[ -z "$issuer" ] && issuer="$(ex "curl -sSL -m 8 '${KC_BASE}/auth/realms/${REALM}/.well-known/openid-configuration'" 2>/dev/null | grep -o '"issuer":"[^"]*"')"
if [ -n "$issuer" ]; then
  echo "      ${issuer}"
  echo "      -> 이 값(따옴표 안 URL)을 .env 의 KEYCLOAK_ISSUER 에 그대로."
else
  echo "      (아직 못 얻음 — 아래 판독 참고)"
fi

cat <<'HINT'

== 판독 ==
- [A]/[B] 'realm' 이 200 인 쪽이 정답 베이스. 둘 다 404 면 -> realm 이름이 'gitlab' 이 아님.
- 'discovery' 가 302 이고 redirect= 가 https:// 로 가면 -> Keycloak 이 http 를 막는 중:
    Keycloak admin -> Realm settings(gitlab) -> General -> Require SSL = None -> 저장 후 이 스크립트 재실행.
- [D] 에서 issuer 가 나오면: .env 에 KEYCLOAK_ISSUER=<그 URL> (http 인지 확인) 후
    set -a; source .env; set +a
    docker compose --env-file .env -f compose/gitlab.compose.yml up -d
HINT
