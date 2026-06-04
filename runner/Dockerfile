# syntax=docker/dockerfile:1
# gitlab-runner + docker CLI + compose plugin + jq, deploy-app/lib 포함.
# shell executor 가 호스트 docker.sock 으로 호스트에 배포한다.
FROM gitlab/gitlab-runner:latest

USER root
# 잡은 gitlab-runner 유저로 실행됨(이미지가 --user gitlab-runner) → 호스트 docker 소켓 접근 위해
# 그 유저를 호스트 docker 그룹 GID 에 넣는다. DOCKER_GID 는 .env 값(getent group docker)으로 전달.
ARG DOCKER_GID=999
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      docker.io docker-compose-v2 jq
RUN if ! getent group "${DOCKER_GID}" >/dev/null; then groupadd -g "${DOCKER_GID}" dockerhost; fi \
 && usermod -aG "$(getent group "${DOCKER_GID}" | cut -d: -f1)" gitlab-runner

COPY scripts/lib/registry.sh /usr/local/lib/deploy/registry.sh
COPY scripts/deploy-app /usr/local/bin/deploy-app
RUN chmod +x /usr/local/bin/deploy-app
RUN mkdir -p /usr/local/bin/lib && \
    ln -sf /usr/local/lib/deploy/registry.sh /usr/local/bin/lib/registry.sh
