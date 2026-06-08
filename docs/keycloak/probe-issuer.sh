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
  echo "      (아직 못 얻음 — 아래 [E] 정체 확인)"
fi

echo "[E] 8080 정체 확인 (realm ${REALM} 이 404 라서 — 여기가 Keycloak 이긴 한가?):"
show "master-disc"  "${KC_BASE}/realms/master/.well-known/openid-configuration"  # KC 면 항상 존재
show "kc-admin"     "${KC_BASE}/admin/master/console/"                           # KC admin 콘솔
show "gitlab-sign"  "${KC_BASE}/users/sign_in"                                   # GitLab 지문
echo "      (root 302 의 redirect= 목적지도 위 [A] root 줄에서 같이 보기)"

cat <<'HINT'

== 판독 ==
- realm 'gitlab' 이 신/구 경로 모두 404 인데 리다이렉트가 http 면 -> SSL 문제 아님. 정체부터 확인:
  * [E] master-disc 또는 kc-admin 이 200/302 -> 여기는 Keycloak 맞음.
        그럼 이 Keycloak 에 'gitlab' realm 이 없는 것 = realm 이름 재확인 or 다른 KC 인스턴스.
  * [E] gitlab-sign 이 200 (또는 [A] root 의 redirect= 가 /users/sign_in) -> 8080 은 'GitLab' 임!
        Keycloak 은 다른 주소/포트에 있다. 진짜 Keycloak 의 host:port 를 찾아 KC_BASE 를 바꿔야 함.
- 정체가 잡히면: 올바른 base 로 discovery 200 확인 -> [D] issuer 값을 .env 의 KEYCLOAK_ISSUER 에
    (http/https 스킴 정확히) -> set -a; source .env; set +a
    -> docker compose --env-file .env -f compose/gitlab.compose.yml up -d
HINT

