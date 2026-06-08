#!/usr/bin/env bash
# probe-issuer.sh — Keycloak OIDC issuer 탐지 헬퍼.
# GitLab 컨테이너 안에서 Keycloak discovery 엔드포인트를 찔러 올바른 issuer/경로를 찾는다.
# 왜: SSL/경로 오설정으로 OIDC 로그인이 깨질 때, .env 의 KEYCLOAK_ISSUER 정답값을 확정하려고.
# 사용: bash docs/keycloak/probe-issuer.sh
set -euo pipefail

# --- 환경 (이 서버 토폴로지) ---
KC_BASE="http://182.199.63.71:8080"   # Keycloak (71서버, http)
REALM="gitlab"
# 참고: GitLab 외부 URL = g-ai-agent.sbiologics.com:2222 (Keycloak client redirect_uri /
#       .env 의 GITLAB_HOSTNAME:GITLAB_HTTP_PORT 용. 아래 issuer 탐지와는 별개)

probe() {                              # $1 = 경로 프리픽스 (""=신버전 | "/auth"=구버전)
  local prefix="$1"
  local url="${KC_BASE}${prefix}/realms/${REALM}/.well-known/openid-configuration"
  local code
  code="$(docker exec gitlab bash -c "curl -sS -m 8 -o /dev/null -w '%{http_code}' '$url'" 2>/dev/null || echo 000)"
  printf '  %-18s realms/%s -> HTTP %s\n' "${prefix:-(no prefix)}" "$REALM" "$code"
  if [ "$code" = "200" ]; then
    echo "  >>> 정답 경로 발견. .well-known 의 issuer:"
    docker exec gitlab bash -c "curl -sS '$url'" | grep -o '"issuer":"[^"]*"' | sed 's/^/      /'
    echo "  >>> .env 에 그대로 넣을 값:"
    echo "      KEYCLOAK_ISSUER=${KC_BASE}${prefix}/realms/${REALM}"
    return 0
  fi
  return 1
}

echo "== Keycloak issuer 탐지 (base=${KC_BASE}, realm=${REALM}) =="

echo "[1] GitLab 컨테이너 -> Keycloak 루트 도달 확인:"
docker exec gitlab bash -c "curl -sS -m 8 -o /dev/null -w '  HTTP %{http_code} -> %{redirect_url}\n' '${KC_BASE}/'" \
  || echo "  (연결 실패 — 컨테이너가 호스트 IP:8080 에 못 닿음. 네트워크 문제)"

echo "[2] discovery 경로 탐색 (신버전 / 구버전 /auth 순):"
if probe "" || probe "/auth"; then
  cat <<'NEXT'

== 다음 단계 ==
1) 위 'KEYCLOAK_ISSUER=' 값을 .env 에 반영 (https 아니라 http 인지 확인):
     nano .env   # 또는: sed -i 's#^KEYCLOAK_ISSUER=.*#<위 값>#' .env
2) Keycloak admin -> Realm settings -> General -> Require SSL = None (http 접근 허용)
3) 반영:
     set -a; source .env; set +a
     docker compose --env-file .env -f compose/gitlab.compose.yml up -d
4) GitLab 로그인에서 "Keycloak" 버튼으로 재시도.
   issuer mismatch 류 에러면: 위 [2]의 issuer 문자열을 '한 글자도 다르지 않게' .env 에.
NEXT
else
  echo "  둘 다 200 아님 -> realm명('${REALM}')/포트(8080)/네트워크 재확인 필요."
fi
