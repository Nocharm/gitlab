# 앱 자동 배포 가이드 (앱 팀용)

**한 줄:** 프로젝트의 protected 브랜치(보통 `main`)에 push하면, 사내 서버의 **자동 할당 포트**로
앱이 배포된다. 재배포하면 같은 포트에서 컨테이너만 교체되고 **데이터는 보존**된다.

> 이 가이드는 *앱을 배포하는 사람* 용이다. GitLab/러너 자체 구축은 [`RUNBOOK.md`](RUNBOOK.md) 참고.

## 전제
- 사내 GitLab에 당신 프로젝트가 있다.
- `shell-71` 태그 러너가 등록돼 있다(운영자가 셋업).
- 레포 **루트에 `Dockerfile`**(단일 이미지) 또는 **`docker-compose.yml`**(스택)이 있다.

## 1. `.gitlab-ci.yml` 추가
[`examples/gitlab-ci.template.yml`](../examples/gitlab-ci.template.yml) 을 프로젝트 루트의
`.gitlab-ci.yml` 로 복사한다. 동작하는 실제 예시는 [`examples/sample-app/`](../examples/sample-app/).

## 2. 변수 (`.gitlab-ci.yml` 의 `variables:`)
| 변수 | 의미 | 예 |
|---|---|---|
| `APP_PORT` | 컨테이너가 listen하는 **내부 포트** (호스트 포트는 자동 할당) | `80`, `8000`, `3000` |
| `DEPLOY_VOLUMES` | 영속 데이터 경로. `vol:/path`, 여러 개면 콤마. 없으면 무상태 | `data:/var/lib/app,uploads:/app/uploads` |

## 3. 동작 방식
- **deploy (자동):** protected 브랜치 push → 이미지 빌드 → 범위에서 **빈 포트 자동 할당**(이미 다른
  프로세스가 쓰는 포트는 자동으로 건너뜀) → 컨테이너 기동. 한 번 할당된 포트는 그 프로젝트가 계속 쓴다.
- **재배포:** 같은 포트 유지, 컨테이너만 교체. **named 볼륨 데이터는 보존**.
- **reset / destroy / purge:** 파이프라인 화면에서 수동 실행.
  - `reset` = 데이터 초기화 후 재배포
  - `destroy` = 서비스만 내림(볼륨 보존)
  - `purge` = 완전 삭제(컨테이너 + 볼륨 + 포트 반납)

## 4. 내 앱이 어느 포트로 떴는지
- 배포 job 로그 **마지막 줄**: `deployed <name> -> :<포트>`.
- 또는 운영자에게 `/srv/deploy/registry.json` 확인 요청.

## 5. 단일 이미지 vs compose
| 형태 | 레포 루트 | ci script |
|---|---|---|
| **단일 이미지** | `Dockerfile` | `deploy-app "$CI_PROJECT_PATH_SLUG"` |
| **compose 스택** | `docker-compose.yml` | `deploy-app "$CI_PROJECT_PATH_SLUG" --compose` |

> compose 스택은 포트 매핑을 자신의 `docker-compose.yml`에서 직접 정의한다.

## 6. 주의 (보안)
- 배포는 **protected 브랜치에서만** 일어난다(`rules:` 로 강제). 일반 MR/브랜치 push는 배포 안 됨.
- `shell-71` 러너는 호스트 docker를 직접 쓰므로 **사실상 호스트 root 권한**이다. 이 러너에 파이프라인을
  돌릴 수 있는 = 서버를 장악할 수 있는 것이니, **신뢰된 프로젝트에만** 러너를 붙인다.

## 7. 안 될 때
job이 pending이거나 배포가 실패하면 [`RUNBOOK.md`의 트러블슈팅 표](RUNBOOK.md#트러블슈팅-실제-겪은-이슈--해결)
를 본다 (태그 불일치, CRLF, 포트/소켓 권한 등 정리돼 있음).
