#!/usr/bin/env bash
# clean_slate.sh — 기존 gitlab/gitlab-runner 컨테이너·볼륨·네트워크 인벤토리 후 정리.
# 무한 pending 의 흔한 원인인 옛 러너 등록 잔재를 제거한다. 확인 프롬프트 포함.
set -euo pipefail

echo "=== 현재 gitlab/runner 관련 리소스 ==="
echo "[containers]"; docker ps -a --filter "name=gitlab" --format '  {{.Names}}\t{{.Status}}'
echo "[volumes]";    docker volume ls --filter "name=gitlab" --format '  {{.Name}}'
echo "[networks]";   docker network ls --filter "name=gitlab" --format '  {{.Name}}'

read -r -p "위 gitlab/gitlab-runner 컨테이너를 중지·삭제할까요? (y/N) " ans
[ "$ans" = "y" ] || { echo "취소됨 (리소스 유지)"; exit 0; }

docker rm -f gitlab gitlab-runner 2>/dev/null || true
echo "컨테이너 정리 완료. 볼륨은 데이터 보존 위해 수동 확인:"
echo "  docker volume rm gitlab_config gitlab_logs gitlab_data runner_config   # 필요 시"
