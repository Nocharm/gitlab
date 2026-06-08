#!/usr/bin/env bash
# probe-issuer.sh — Keycloak OIDC issuer/경로 진단 헬퍼 (서버에서 pull 후 실행만).
# GitLab 컨테이너 안에서 Keycloak 을 여러 경로로 찔러 realm 존재·SSL 리다이렉트·issuer 를 한 번에 본다.
# 왜: OIDC 로그인이 SSL/경로 오설정으로 깨질 때 .env 의 KEYCLOAK_ISSUER 정답값을 확정하려고.
# 사용: bash docs/keycloak/probe-issuer.sh
set -uo pipefail   # -e 제외: 진단이라 일부 curl 실패해도 계속 진행

# --- 환경 (이 서버 토폴로지) ---
KC_BASE="http://182.199.63.71:8080"   # Keycloak (71서버, http)
REALM="ai-portal"                     # realm 이름 (client id 'gitlab' 과 혼동 주의 — issuer 는 realm 기준)
# 참고: client id = gitlab (.env 의 KEYCLOAK_CLIENT_ID), GitLab 외부 URL = g-ai-agent.sbiologics.com:2222
#       (Keycloak client redirect_uri / .env 의 GITLAB_HOSTNAME:GITLAB_HTTP_PORT 용. issuer 와는 별개)

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

echo "[F] 적용 상태 점검 (여전히 https 로 붙는 원인):"
echo "  (1) .env 값 (secret 제외):"
grep -E '^KEYCLOAK_(ISSUER|CLIENT_ID)=' .env 2>/dev/null | sed 's/^/      /' || echo "      (.env 못 읽음 — repo 루트에서 실행)"
echo "  (2) GitLab 이 실제 로드한 issuer (= up -d 반영 여부):"
loaded="$(docker exec gitlab bash -c "grep -i issuer /var/opt/gitlab/gitlab-rails/etc/gitlab.yml 2>/dev/null" 2>/dev/null)"
[ -n "$loaded" ] && echo "$loaded" | sed 's/^/      /' || echo "      (못 찾음 — 아직 reconfigure 안 됐거나 provider 미적용)"
echo "  (3) discovery 가 광고하는 엔드포인트 스킴(http/https):"
ex "curl -sSL -m8 '${KC_BASE}/realms/${REALM}/.well-known/openid-configuration'" 2>/dev/null \
  | tr ',{' '\n\n' \
  | grep -E '"(issuer|authorization_endpoint|token_endpoint|userinfo_endpoint|jwks_uri)"[[:space:]]*:' \
  | sed 's/^/      /'

cat <<'HINT'

== 판독 ==
- realm 'ai-portal' discovery 가 200 인데 GitLab 은 여전히 https 로 붙어 깨지면:
  * [F](2) 가 비어있거나 예전 https 값 -> .env 편집 후 'up -d' 를 안/잘못 돌린 것.
        반드시: set -a; source .env; set +a
                docker compose --env-file .env -f compose/gitlab.compose.yml up -d   (Recreating gitlab 확인, 3~5분)
  * [F](3) 의 endpoint 가 https://182.199.63.71:8080/... 로 광고됨 -> 진짜 원인.
        issuer 를 http 로 둬도 GitLab 은 token/userinfo 를 https:8080 으로 붙어 'record layer failure'.
        => 해결은 Keycloak 쪽: 이 KC 가 광고하는 'issuer'(=[F](3) 의 issuer) 를 그대로 KEYCLOAK_ISSUER 에 쓰고,
           GitLab 이 그 주소(스킴 포함)로 실제 도달 가능해야 함. KC 가 https 공개 URL 이면 그 https URL 을,
           http 백엔드면 KC hostname 설정을 http 로 맞춰야 함(인프라/KC 관리자 조정).
- 즉 KEYCLOAK_ISSUER 는 'IP:8080 추측' 이 아니라 [F](3) 가 광고하는 issuer 문자열과 '글자 그대로' 같아야 함.
HINT


