#!/usr/bin/env bash
# register_runner.sh — 러너를 shell executor 로 등록 (GitLab 16.6+ authentication token 방식).
# 태그/locked/run-untagged 등은 UI에서 러너 생성 시 설정 — register에 넘기면 FATAL(reserved).
# 여기선 url/token/executor 만 넘긴다. .env 의 CI_SERVER_URL / RUNNER_TOKEN 사용. 서버에서 실행.
set -euo pipefail

: "${CI_SERVER_URL:?set CI_SERVER_URL}"
: "${RUNNER_TOKEN:?set RUNNER_TOKEN}"

docker exec gitlab-runner gitlab-runner register --non-interactive \
  --url "$CI_SERVER_URL" \
  --token "$RUNNER_TOKEN" \
  --executor shell

echo "등록 완료. 확인: docker exec gitlab-runner gitlab-runner verify"
