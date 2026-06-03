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
