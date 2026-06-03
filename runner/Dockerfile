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
RUN mkdir -p /usr/local/bin/lib && \
    ln -sf /usr/local/lib/deploy/registry.sh /usr/local/bin/lib/registry.sh
